defmodule Escalated.TicketRoutingTest do
  use Escalated.DataCase, async: false
  alias Ecto.Changeset
  alias Escalated.Schemas.{Automation, Department, EscalationRule, SlaPolicy, Ticket, Workflow}

  alias Escalated.Services.{
    AutomationRunner,
    EscalationService,
    SlaService,
    TicketService,
    TicketSubjectService,
    WorkflowRunner
  }

  setup do
    Application.put_env(:escalated, :sla, %{enabled: true, business_hours_only: false})

    Application.put_env(:escalated, :accounts, %{
      enabled: true,
      resolver: fn
        :requester, "user", 100 -> %{type: "Company", id: "ACME"}
        :subject, "Project", "one" -> %{type: "Company", id: "FIRST"}
        :subject, "Project", "two" -> %{type: "Company", id: "SECOND"}
        _, _, _ -> nil
      end
    })

    on_exit(fn ->
      for key <- [:sla, :accounts, :targeted_slas], do: Application.delete_env(:escalated, key)
    end)

    :ok
  end

  test "requester and first subject resolve accounts without public field assignment" do
    {:ok, requester} =
      TicketService.create(%{
        subject: "Requester",
        description: "Body",
        requester_type: "user",
        requester_id: 100,
        account_type: "Injected",
        account_id: "bad"
      })

    assert {requester.account_type, requester.account_id} == {"Company", "ACME"}

    {:ok, empty} =
      TicketService.create(%{
        subject: "Subject",
        description: "Body",
        account_type: "Injected",
        account_id: "bad"
      })

    assert is_nil(empty.account_id)

    for id <- ["one", "two"] do
      assert {:ok, _} =
               TicketSubjectService.attach_subject(empty, "Project", id, enforce_allowlist: false)

      assert {:ok, _} =
               TicketSubjectService.attach_subject(requester, "Project", id,
                 enforce_allowlist: false
               )
    end

    assert Escalated.repo().get!(Ticket, empty.id).account_id == "FIRST"
    assert Escalated.repo().get!(Ticket, requester.id).account_id == "ACME"
  end

  for engine <- [:workflow, :automation, :escalation],
      {name, value, expected} <- [
        {"complete pair", %{"type" => "Company", "id" => "ACME"}, "urgent"},
        {"case mismatch", %{"type" => "Company", "id" => "acme"}, "medium"},
        {"incomplete pair", %{"id" => "ACME"}, "medium"}
      ] do
    test "#{engine} routes by ticket type and #{name}" do
      {:ok, ticket} =
        TicketService.create(%{
          subject: "Rules",
          description: "Body",
          requester_type: "user",
          requester_id: 100,
          ticket_type: "task"
        })

      conditions = [
        %{"field" => "ticket_type", "operator" => "equals", "value" => "task"},
        %{"field" => "account", "operator" => "equals", "value" => unquote(Macro.escape(value))}
      ]

      actions = [%{"type" => "change_priority", "value" => "urgent"}]
      execute(unquote(engine), conditions, actions, ticket)
      assert Escalated.repo().get!(Ticket, ticket.id).priority == unquote(expected)
    end
  end

  test "malformed account negation never matches" do
    refute Escalated.Services.WorkflowEngine.evaluate_conditions(
             [%{"field" => "account", "operator" => "not_equals", "value" => %{"id" => "A"}}],
             %Ticket{}
           )
  end

  test "targeted SLAs rank department plus type, department, type and default from creation time" do
    Application.put_env(:escalated, :targeted_slas, true)
    a = Escalated.repo().insert!(Department.changeset(%Department{}, %{name: "Alpha"}))
    b = Escalated.repo().insert!(Department.changeset(%Department{}, %{name: "Beta"}))
    default = policy("Default", %{is_default: true}, 24)
    type = policy("Type", %{ticket_type: "task"}, 12)
    dept = policy("Department", %{department_id: a.id}, 8)
    both = policy("Both", %{department_id: a.id, ticket_type: "task"}, 2)
    policy("Tie loses", %{department_id: a.id, ticket_type: "task"}, 1)

    {:ok, ticket} =
      TicketService.create(%{
        subject: "SLA",
        description: "Body",
        department_id: a.id,
        ticket_type: "task"
      })

    created = Escalated.repo().get!(Ticket, ticket.id)
    assert created.sla_policy_id == both.id
    assert DateTime.diff(created.sla_resolution_due_at, created.inserted_at) == 7200
    {:ok, moved} = TicketService.change_department(created, b)
    assert moved.sla_policy_id == both.id
    assert moved.sla_resolution_due_at == created.sla_resolution_due_at
    {:ok, reselected} = SlaService.attach_policy(moved)
    assert reselected.sla_policy_id == type.id
    assert DateTime.diff(reselected.sla_resolution_due_at, reselected.inserted_at) == 43_200

    {:ok, department_ticket} =
      TicketService.create(%{subject: "Dept", description: "Body", department_id: a.id})

    assert Escalated.repo().get!(Ticket, department_ticket.id).sla_policy_id == dept.id
    {:ok, fallback} = TicketService.create(%{subject: "Fallback", description: "Body"})
    assert Escalated.repo().get!(Ticket, fallback.id).sla_policy_id == default.id
  end

  test "accounts and targeted SLA selection default off" do
    Application.delete_env(:escalated, :accounts)
    Application.delete_env(:escalated, :targeted_slas)
    policy("Targeted default", %{ticket_type: "task", is_default: true}, 1)

    {:ok, ticket} =
      TicketService.create(%{
        subject: "Legacy",
        description: "Body",
        requester_type: "user",
        requester_id: 100,
        ticket_type: "task"
      })

    stored = Escalated.repo().get!(Ticket, ticket.id)
    assert is_nil(stored.account_id)
    assert is_nil(stored.sla_policy_id)
  end

  defp policy(name, target, hours) do
    attrs =
      Map.merge(
        %{
          name: name,
          first_response_hours: %{"medium" => hours},
          resolution_hours: %{"medium" => hours}
        },
        target
      )

    Escalated.repo().insert!(SlaPolicy.changeset(%SlaPolicy{}, attrs))
  end

  defp execute(:workflow, conditions, actions, ticket) do
    Escalated.repo().insert!(
      Changeset.change(%Workflow{},
        name: "Workflow",
        trigger_event: "ticket.updated",
        conditions: %{"all" => conditions},
        actions: actions
      )
    )

    WorkflowRunner.run_for_event("ticket.updated", ticket)
  end

  defp execute(:automation, conditions, actions, _ticket) do
    Escalated.repo().insert!(
      Changeset.change(%Automation{},
        name: "Automation",
        conditions: conditions,
        actions: actions
      )
    )

    AutomationRunner.run(Escalated.repo())
  end

  defp execute(:escalation, conditions, actions, _ticket) do
    Escalated.repo().insert!(
      Changeset.change(%EscalationRule{},
        name: "Escalation",
        conditions: conditions,
        actions: actions
      )
    )

    EscalationService.evaluate_rules(Escalated.repo())
  end
end
