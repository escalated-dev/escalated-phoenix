defmodule Escalated.Controllers.Admin.WorkflowContractTest do
  @moduledoc """
  The Workflows admin surface, checked against the wire contract in
  escalated-developer-context/domain-model/workflow-admin-contract.md.

  Every request goes through a real router (`Escalated.Test.Router`) as an
  Inertia visit, and every body is the one the shared builder sends. The older
  tests posted this backend's own field names straight at the controller
  functions, which is how a missing create page, a missing edit route and
  missing toggle/reorder routes all shipped behind a green suite.
  """
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  require Ecto.Query

  alias Escalated.Schemas.{Department, Reply, Ticket, Workflow, WorkflowLog}
  alias Escalated.Services.{TicketService, WorkflowExecutor}
  alias Escalated.Test.Router

  @index "/support/admin/workflows"

  @core_actions ~w(change_status change_priority add_tag remove_tag set_department assign_agent add_note insert_canned_reply)

  @contract_operators ~w(equals not_equals contains not_contains starts_with ends_with greater_than less_than greater_or_equal less_or_equal is_empty is_not_empty)

  defp repo, do: Escalated.repo()

  # The example body from the contract, verbatim except for the department id,
  # which has to name a department that exists in this database.
  defp contract_body(department_id) do
    %{
      "name" => "Route refunds to billing",
      "description" => nil,
      "trigger_event" => "ticket.created",
      "conditions" => %{
        "all" => [%{"field" => "subject", "operator" => "contains", "value" => "refund"}]
      },
      "actions" => [
        %{"type" => "change_priority", "value" => "high"},
        %{"type" => "set_department", "value" => to_string(department_id)}
      ],
      "is_active" => true
    }
  end

  defp department! do
    %Department{} |> Department.changeset(%{name: "Billing"}) |> repo().insert!()
  end

  defp workflow!(attrs) do
    %Workflow{}
    |> Workflow.changeset(
      Map.merge(
        %{
          name: "WF",
          trigger_event: "ticket.created",
          conditions: %{"all" => []},
          actions: [%{"type" => "change_priority", "value" => "high"}]
        },
        attrs
      )
    )
    |> repo().insert!()
  end

  # An Inertia visit through the router. The version header has to match what
  # Inertia.Plug computes, or a GET is answered with a 409 force-refresh.
  defp visit(method, path, body \\ nil, headers \\ []) do
    base =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    headers
    |> Enum.reduce(base, fn {k, v}, conn -> put_req_header(conn, k, v) end)
    |> init_test_session(%{})
    |> assign(:current_user, %{id: 1})
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> Router.call(Router.init([]))
  end

  defp inertia_version do
    conn(:get, "/")
    |> init_test_session(%{})
    |> Inertia.Plug.call(Inertia.Plug.init([]))
    |> Map.fetch!(:private)
    |> Map.fetch!(:inertia_version)
    |> to_string()
  end

  defp page(conn) do
    assert conn.status == 200, "expected a rendered page, got #{conn.status}: #{conn.resp_body}"
    Jason.decode!(conn.resp_body)
  end

  defp location(conn), do: conn |> get_resp_header("location") |> List.first()

  # Inertia keeps the errors in the session as the map it was given, keyed by
  # field atom; they only become strings when the next page is serialised.
  defp session_errors(conn) do
    errors = get_session(conn, "inertia_errors") || %{}
    Map.new(errors, fn {field, message} -> {to_string(field), message} end)
  end

  defp option_values(options) when is_list(options) do
    Enum.map(options, fn
      %{"value" => value} -> value
      value when is_binary(value) -> value
    end)
  end

  defp option_values(options) when is_map(options), do: Map.keys(options)

  describe "create (contract check 1)" do
    test "stores the builder's body with the same trigger_event, conditions and actions" do
      dept = department!()
      body = contract_body(dept.id)

      conn = visit(:post, "#{@index}", body)

      assert conn.status == 302
      assert location(conn) == @index

      [wf] = repo().all(Workflow)
      assert wf.name == "Route refunds to billing"
      assert wf.description == nil
      assert wf.trigger_event == body["trigger_event"]
      assert wf.conditions == body["conditions"]
      assert wf.actions == body["actions"]
      assert wf.is_active == true
    end

    test "omitted conditions are stored as {\"all\": []}" do
      body = department!().id |> contract_body() |> Map.delete("conditions")

      conn = visit(:post, @index, body)

      assert conn.status == 302
      [wf] = repo().all(Workflow)
      assert wf.conditions == %{"all" => []}
    end

    test "a body with no actions is refused, with the errors in the session" do
      body = department!().id |> contract_body() |> Map.delete("actions")

      conn = visit(:post, @index, body, [{"referer", "#{@index}/new"}])

      assert conn.status == 302
      assert location(conn) == "#{@index}/new"
      assert Map.has_key?(session_errors(conn), "actions")
      assert repo().all(Workflow) == []
    end

    test "an empty actions list is refused" do
      body = department!().id |> contract_body() |> Map.put("actions", [])

      conn = visit(:post, @index, body)

      assert conn.status == 302
      assert Map.has_key?(session_errors(conn), "actions")
      assert repo().all(Workflow) == []
    end

    test "name and trigger_event are required" do
      body =
        department!().id
        |> contract_body()
        |> Map.drop(["name", "trigger_event"])

      conn = visit(:post, @index, body)

      assert conn.status == 302
      errors = session_errors(conn)
      assert Map.has_key?(errors, "name")
      assert Map.has_key?(errors, "trigger_event")
      assert repo().all(Workflow) == []
    end
  end

  describe "update" do
    test "PUT with the builder's body replaces the stored workflow" do
      dept = department!()
      wf = workflow!(%{name: "Old", trigger_event: "reply.created"})
      body = contract_body(dept.id)

      conn = visit(:put, "#{@index}/#{wf.id}", body)

      assert conn.status == 303
      assert location(conn) == @index

      reloaded = repo().get!(Workflow, wf.id)
      assert reloaded.name == body["name"]
      assert reloaded.trigger_event == body["trigger_event"]
      assert reloaded.conditions == body["conditions"]
      assert reloaded.actions == body["actions"]
    end

    test "PUT with no actions is refused and leaves the workflow alone" do
      wf = workflow!(%{name: "Keep me"})
      body = department!().id |> contract_body() |> Map.put("actions", [])

      conn = visit(:put, "#{@index}/#{wf.id}", body)

      assert conn.status == 303
      assert Map.has_key?(session_errors(conn), "actions")
      assert repo().get!(Workflow, wf.id).name == "Keep me"
    end
  end

  describe "execution (contract check 2)" do
    test "a workflow saved through the endpoint runs its actions when its event fires" do
      dept = department!()
      assert visit(:post, @index, contract_body(dept.id)).status == 302

      {:ok, ticket} =
        TicketService.create(%{subject: "I would like a refund", description: "please"})

      reloaded = repo().get!(Ticket, ticket.id)
      assert reloaded.priority == "high"
      assert reloaded.department_id == dept.id
    end

    test "a ticket that does not match the saved conditions is left alone" do
      dept = department!()
      assert visit(:post, @index, contract_body(dept.id)).status == 302

      {:ok, ticket} = TicketService.create(%{subject: "Password reset", description: "please"})

      reloaded = repo().get!(Ticket, ticket.id)
      assert reloaded.priority == "medium"
      assert reloaded.department_id == nil
    end

    test "an empty \"any\" list matches every ticket" do
      body =
        department!().id
        |> contract_body()
        |> Map.put("conditions", %{"any" => []})

      assert visit(:post, @index, body).status == 302

      {:ok, ticket} = TicketService.create(%{subject: "Anything at all", description: "x"})

      assert repo().get!(Ticket, ticket.id).priority == "high"
    end
  end

  describe "form props (contract check 3)" do
    test "the create page renders the Form with a null workflow and the option lists" do
      body = @index |> Kernel.<>("/new") |> then(&visit(:get, &1)) |> page()

      assert body["component"] == "Escalated/Admin/Workflows/Form"
      props = body["props"]
      assert Map.has_key?(props, "workflow")
      assert props["workflow"] == nil
      assert [_ | _] = option_values(props["trigger_events"])
      assert [_ | _] = option_values(props["action_types"])
      assert [_ | _] = option_values(props["operators"])
    end

    test "the edit page renders the Form with the workflow and the option lists" do
      wf = workflow!(%{name: "Existing"})

      body = visit(:get, "#{@index}/#{wf.id}/edit") |> page()

      assert body["component"] == "Escalated/Admin/Workflows/Form"
      props = body["props"]
      assert props["workflow"]["id"] == wf.id
      assert props["workflow"]["trigger_event"] == "ticket.created"
      assert props["workflow"]["conditions"] == %{"all" => []}
      assert [_ | _] = option_values(props["trigger_events"])
      assert [_ | _] = option_values(props["action_types"])
    end

    test "trigger_events lists exactly the events that are fired" do
      advertised =
        visit(:get, "#{@index}/new")
        |> page()
        |> get_in(["props", "trigger_events"])
        |> option_values()

      assert Enum.sort(advertised) ==
               Enum.sort(~w(ticket.created reply.created ticket.status_changed))

      # And each one really does run a workflow saved against it.
      for event <- advertised do
        wf = workflow!(%{name: "on #{event}", trigger_event: event})
        ticket = fire!(event)

        assert repo().get_by(WorkflowLog, workflow_id: wf.id, ticket_id: ticket.id),
               "#{event} is offered in the builder but never ran its workflow"
      end
    end

    test "action_types lists the core catalog, and nothing the executor cannot run" do
      advertised =
        visit(:get, "#{@index}/new")
        |> page()
        |> get_in(["props", "action_types"])
        |> option_values()

      assert @core_actions -- advertised == []

      for type <- advertised do
        result = WorkflowExecutor.dispatch_action(%Ticket{}, %{"type" => type, "value" => ""})

        refute match?({:error, _, reason} when reason in [:unknown, :handled_in_execute], result),
               "#{type} is offered in the builder but the executor does not run it from a saved workflow"
      end
    end

    test "operators includes every operator the contract requires" do
      advertised =
        visit(:get, "#{@index}/new")
        |> page()
        |> get_in(["props", "operators"])
        |> option_values()

      assert @contract_operators -- advertised == []
    end
  end

  describe "index" do
    test "renders the workflow objects" do
      wf = workflow!(%{name: "Listed"})

      body = visit(:get, @index) |> page()

      assert body["component"] == "Escalated/Admin/Workflows/Index"
      [listed] = body["props"]["workflows"]
      assert listed["id"] == wf.id
      assert listed["trigger_event"] == "ticket.created"
      assert listed["is_active"] == true
      assert is_integer(listed["position"])
    end
  end

  describe "toggle" do
    test "POST flips is_active and redirects to the index" do
      wf = workflow!(%{is_active: true})

      conn = visit(:post, "#{@index}/#{wf.id}/toggle")
      assert conn.status == 302
      assert location(conn) == @index
      assert repo().get!(Workflow, wf.id).is_active == false

      visit(:post, "#{@index}/#{wf.id}/toggle")
      assert repo().get!(Workflow, wf.id).is_active == true
    end
  end

  describe "reorder" do
    test "POST workflow_ids stores that order" do
      a = workflow!(%{name: "A", position: 1})
      b = workflow!(%{name: "B", position: 2})
      c = workflow!(%{name: "C", position: 3})

      conn = visit(:post, "#{@index}/reorder", %{"workflow_ids" => [c.id, a.id, b.id]})

      assert conn.status == 302
      assert location(conn) == @index

      ordered =
        Workflow
        |> Ecto.Query.order_by(asc: :position)
        |> repo().all()
        |> Enum.map(& &1.name)

      assert ordered == ["C", "A", "B"]
    end
  end

  describe "delete" do
    test "DELETE removes the workflow and redirects to the index" do
      wf = workflow!(%{})

      conn = visit(:delete, "#{@index}/#{wf.id}")

      assert conn.status == 303
      assert location(conn) == @index
      assert repo().get(Workflow, wf.id) == nil
    end
  end

  defp fire!("ticket.created") do
    {:ok, ticket} = TicketService.create(%{subject: "Created", description: "x"})
    ticket
  end

  defp fire!("reply.created") do
    ticket = plain_ticket!()

    {:ok, %Reply{}} =
      TicketService.reply(ticket, %{body: "hi", is_internal: false, author_id: nil})

    ticket
  end

  defp fire!("ticket.status_changed") do
    ticket = plain_ticket!()
    {:ok, _} = TicketService.transition_status(ticket, "resolved")
    ticket
  end

  # Inserted without TicketService, so creating it fires nothing.
  defp plain_ticket! do
    %Ticket{}
    |> Ticket.changeset(%{subject: "S", description: "D", priority: "medium"})
    |> repo().insert!()
  end
end
