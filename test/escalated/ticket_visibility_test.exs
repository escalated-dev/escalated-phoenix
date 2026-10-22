defmodule Escalated.TicketVisibilityTest do
  use Escalated.DataCase, async: false
  import Ecto.Query
  import Plug.Conn
  import Plug.Test
  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Changeset
  alias Escalated.{HostTestRepo, TicketVisibility}

  alias Escalated.Schemas.{
    Department,
    DepartmentAgent,
    Reply,
    SideConversation,
    SideConversationReply,
    Ticket,
    TicketLink
  }

  alias Escalated.Services.{AssignmentService, SlaService, TicketService}
  alias Escalated.Test.{HostUser, Router}
  @agent %{id: 900, is_agent: true}

  test "rejected creation rolls back the ticket and its side effects", c do
    TicketVisibility.with_user(@agent, fn ->
      assert_raise TicketVisibility.Error, fn ->
        TicketService.create(%{subject: "Outside", description: "Denied", department_id: c.b.id})
      end
    end)

    assert Escalated.repo().aggregate(Ticket, :count) == 2
  end

  test "delivery reloads current roles from the separate host user database", c do
    Application.delete_env(:escalated, :access_user_resolver)
    user = HostTestRepo.insert!(%HostUser{id: 900, name: "Agent", is_agent: true})
    assert TicketVisibility.recipients(c.allowed, [900]) == [900]
    HostTestRepo.update!(Changeset.change(user, is_agent: false))
    assert TicketVisibility.recipients(c.allowed, [900]) == []
  end

  test "account and type filters narrow the HTTP list", c do
    Escalated.repo().update!(
      Changeset.change(c.allowed, account_type: "Company", account_id: "A", ticket_type: "task")
    )

    visible =
      request(:get, "/support/api/v1/tickets?account_type=Company&account_id=A&ticket_type=task")

    assert visible.resp_body =~ c.allowed.reference

    for query <- ["account_id=A", "account_type=Company&account_id=a", "ticket_type=incident"] do
      assert Jason.decode!(request(:get, "/support/api/v1/tickets?" <> query).resp_body)["data"] ==
               []
    end
  end

  test "chat routing filters candidates before selecting an available agent", c do
    alias Escalated.Schemas.ChatRoutingRule

    Escalated.repo().insert!(
      ChatRoutingRule.changeset(%ChatRoutingRule{}, %{name: "Chat", agent_ids: [901, 900]})
    )

    assert {:ok, 900} =
             Escalated.Services.ChatRoutingService.find_available_agent(c.a.id, c.allowed)

    assert {:ok, nil} =
             Escalated.Services.ChatRoutingService.find_available_agent(c.b.id, c.hidden)
  end

  test "department moves complete their activity and restore the requesting actor", c do
    TicketVisibility.with_user(@agent, fn ->
      assert {:ok, moved} = TicketService.change_department(c.allowed, c.b)
      assert moved.department_id == c.b.id
      assert is_nil(TicketService.find(c.allowed.id))
    end)

    assert Escalated.repo().exists?(
             from(a in Escalated.Schemas.TicketActivity,
               where: a.ticket_id == ^c.allowed.id and a.action == "department_changed"
             )
           )
  end

  test "tenant isolation and department visibility compose on separate host storage", c do
    HostTestRepo.insert!(%HostUser{id: 900, name: "a", is_agent: true})
    raw = Escalated.storage_repo()
    raw.update!(Changeset.change(c.a, tenant_id: "a"))
    raw.update!(Changeset.change(c.allowed, tenant_id: "a"))
    raw.update!(Changeset.change(c.member, tenant_id: "a"))
    # Even corrupt imported data naming another tenant's department stays hidden.
    raw.update!(Changeset.change(c.hidden, tenant_id: "b", department_id: c.a.id))
    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, Escalated.Test.TenantResolver)

    on_exit(fn ->
      Application.delete_env(:escalated, :tenancy_enabled)
      Application.delete_env(:escalated, :tenant_resolver)
    end)

    Escalated.Tenancy.run("a", fn ->
      TicketVisibility.with_user(@agent, fn ->
        assert [c.allowed.id] == Enum.map(Escalated.repo().all(Ticket), & &1.id)
      end)
    end)
  end

  setup do
    :ok = Sandbox.checkout(HostTestRepo)
    Sandbox.mode(HostTestRepo, {:shared, self()})
    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :user_schema, HostUser)
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
    Application.put_env(:escalated, :admin_check, &Map.get(&1, :is_admin, false))

    Application.put_env(:escalated, :access_user_resolver, fn
      900 -> @agent
      901 -> %{id: 901, is_agent: true}
      999 -> %{id: 999, is_admin: true, is_agent: true}
      _ -> nil
    end)

    Application.put_env(:escalated, :visibility, :department)

    on_exit(fn ->
      for key <- [
            :user_repo,
            :user_schema,
            :agent_check,
            :admin_check,
            :visibility,
            :accounts,
            :access_user_resolver,
            :api_token_validator
          ] do
        Application.delete_env(:escalated, key)
      end

      Sandbox.checkin(HostTestRepo)
    end)

    a = Escalated.repo().insert!(Department.changeset(%Department{}, %{name: "Alpha"}))
    b = Escalated.repo().insert!(Department.changeset(%Department{}, %{name: "Beta"}))

    member =
      Escalated.repo().insert!(
        DepartmentAgent.changeset(%DepartmentAgent{}, %{department_id: a.id, agent_id: 900})
      )

    {:ok, allowed} =
      TicketService.create(%{subject: "Shared Alpha", description: "Visible", department_id: a.id})

    {:ok, hidden} =
      TicketService.create(%{subject: "Shared Beta", description: "Hidden", department_id: b.id})

    %{allowed: allowed, hidden: hidden, a: a, b: b, member: member}
  end

  @tag :visibility_control
  test "scope intersects OR search, explicit filters and pagination", c do
    TicketVisibility.with_user(@agent, fn ->
      query =
        from(t in Ticket, where: t.id == ^c.allowed.id, or_where: t.id == ^c.hidden.id, limit: 1)

      assert [c.allowed.id] == Enum.map(Escalated.repo().all(query), & &1.id)
      assert [] == TicketService.list(%{department_id: c.b.id})
      assert [c.allowed.id] == Enum.map(TicketService.list(%{search: "shared"}), & &1.id)
    end)
  end

  @tag :visibility_control
  test "reports and aggregates only count permitted tickets", c do
    Escalated.repo().update!(Changeset.change(c.hidden, sla_breached: true))

    TicketVisibility.with_user(@agent, fn ->
      assert Escalated.repo().aggregate(Ticket, :count) == 1
      assert SlaService.stats().total_breached == 0
    end)

    response = request(:get, "/support/agent/dashboard")
    # The dashboard sends Laravel's stat keys, which the shared page reads.
    stats = Jason.decode!(response.resp_body)["props"]["stats"]
    assert stats["open"] == 1
    assert stats["sla_breached"] == 0
  end

  @tag :visibility_control
  test "bulk updates and deletes scope before writing", c do
    TicketVisibility.with_user(@agent, fn ->
      assert {1, _} = Escalated.repo().update_all(Ticket, set: [priority: "urgent"])
      assert {0, _} = Escalated.repo().delete_all(from(t in Ticket, where: t.id == ^c.hidden.id))
      assert {:ok, [_]} = AssignmentService.bulk_unassign([c.allowed.id, c.hidden.id])
    end)

    assert Escalated.repo().get!(Ticket, c.hidden.id).priority == "medium"
  end

  @tag :visibility_control
  test "direct children, nested threads, both link ends and preloads are scoped", c do
    for ticket <- [c.allowed, c.hidden] do
      {:ok, _} = TicketService.reply(ticket, %{body: "Reply"})

      thread =
        Escalated.repo().insert!(
          SideConversation.changeset(%SideConversation{}, %{
            ticket_id: ticket.id,
            subject: "Thread",
            channel: "internal"
          })
        )

      Escalated.repo().insert!(
        SideConversationReply.changeset(%SideConversationReply{}, %{
          side_conversation_id: thread.id,
          body: "Private"
        })
      )
    end

    Escalated.repo().insert!(
      TicketLink.changeset(%TicketLink{}, %{
        parent_ticket_id: c.allowed.id,
        child_ticket_id: c.hidden.id,
        link_type: "related"
      })
    )

    TicketVisibility.with_user(@agent, fn ->
      assert Escalated.repo().aggregate(Reply, :count) == 1
      assert Escalated.repo().aggregate(SideConversationReply, :count) == 1
      assert Escalated.repo().all(TicketLink) == []
      assert length(Escalated.repo().preload(c.allowed, :replies).replies) == 1
      assert_raise TicketVisibility.Error, fn -> Escalated.repo().preload(c.hidden, :replies) end
    end)
  end

  @tag :visibility_control
  test "preloaded services and direct writes cannot bypass visibility", c do
    {:ok, reply} = TicketService.reply(c.allowed, %{body: "Reply"})

    TicketVisibility.with_user(@agent, fn ->
      assert_raise TicketVisibility.Error, fn ->
        TicketService.reply(c.hidden, %{body: "Denied"})
      end

      assert_raise TicketVisibility.Error, fn ->
        Escalated.repo().update!(Changeset.change(c.hidden, subject: "Denied"))
      end

      assert_raise TicketVisibility.Error, fn ->
        Escalated.repo().update!(Changeset.change(reply, ticket_id: c.hidden.id))
      end
    end)
  end

  test "admins, default-off settings and actorless workers retain access", c do
    assert Escalated.repo().aggregate(Ticket, :count) == 2

    TicketVisibility.with_user(%{id: 999, is_agent: true, is_admin: true}, fn ->
      assert TicketService.find(c.hidden.id)
    end)

    Application.put_env(:escalated, :visibility, :all)

    TicketVisibility.with_user(@agent, fn ->
      assert Escalated.repo().aggregate(Ticket, :count) == 2
    end)
  end

  test "nested actor context restores after exceptions", c do
    TicketVisibility.with_user(@agent, fn ->
      assert_raise RuntimeError, fn ->
        TicketVisibility.with_user(nil, fn ->
          assert TicketService.find(c.hidden.id)
          raise "restore"
        end)
      end

      assert is_nil(TicketService.find(c.hidden.id))
    end)

    assert is_nil(TicketVisibility.actor())
  end

  @tag :visibility_control
  test "account restrictions intersect departments with exact pairs", c do
    Escalated.repo().update!(
      Changeset.change(c.allowed, account_type: "Company", account_id: "Å-001")
    )

    Escalated.repo().update!(
      Changeset.change(c.hidden, account_type: "Company", account_id: "Å-001")
    )

    for {id, count} <- [{"Å-001", 1}, {"å-001", 0}, {"Å-001 ", 0}, {nil, 0}] do
      Application.put_env(:escalated, :accounts, %{
        enabled: true,
        scope_agents: true,
        resolver: fn _, _, _ -> %{type: "Company", id: id} end
      })

      TicketVisibility.with_user(@agent, fn ->
        assert Escalated.repo().aggregate(Ticket, :count) == count
      end)
    end
  end

  test "escalation rules and macros cannot assign a ticket to an agent outside its department",
       c do
    alias Escalated.Schemas.{EscalationRule, Macro}
    alias Escalated.Services.{EscalationService, MacroService}

    Escalated.repo().insert!(
      EscalationRule.changeset(%EscalationRule{}, %{
        name: "assign outsider",
        trigger_type: "cron",
        conditions: [%{"field" => "department_id", "value" => c.a.id}],
        actions: [%{"type" => "assign_to", "value" => 901}]
      })
    )

    EscalationService.evaluate_rules(Escalated.repo())
    assert is_nil(Escalated.repo().get!(Ticket, c.allowed.id).assigned_to)

    macro =
      Escalated.repo().insert!(
        Macro.changeset(%Macro{}, %{name: "m", actions: [%{"type" => "assign", "value" => 901}]})
      )

    assert is_nil(MacroService.apply(Escalated.repo(), macro, c.allowed, 999).assigned_to)

    macro =
      Escalated.repo().update!(
        Changeset.change(macro, actions: [%{"type" => "assign", "value" => 900}])
      )

    assert MacroService.apply(Escalated.repo(), macro, c.allowed, 999).assigned_to == 900
  end

  test "assignment and recipient filtering reject outsiders and revoked memberships", c do
    assert_raise TicketVisibility.Error, fn -> AssignmentService.assign(c.allowed, 901) end
    assert {:ok, _} = AssignmentService.assign(c.allowed, 900)
    assert TicketVisibility.recipients(c.allowed, [900, 901, 999]) == [900, 999]
    Escalated.repo().delete!(c.member)
    assert TicketVisibility.recipients(c.allowed, [900, 999]) == [999]
  end

  @tag :visibility_control
  test "agent list and detail use the same scope", c do
    response = request(:get, "/support/agent/tickets")
    assert response.status == 200
    assert response.resp_body =~ c.allowed.reference
    refute response.resp_body =~ c.hidden.reference
    assert request(:get, "/support/agent/tickets/#{c.hidden.reference}").status == 404
    assert request(:get, "/support/agent/tickets/#{c.allowed.reference}").status == 200
  end

  @tag :visibility_control
  test "bearer owner overrides an admin session and request actors are cleared", c do
    Application.put_env(:escalated, :api_token_validator, fn _ -> {:ok, @agent} end)

    response =
      request(:get, "/support/api/v1/tickets/#{c.hidden.reference}", %{id: 999, is_admin: true}, [
        {"authorization", "Bearer agent"}
      ])

    assert response.status == 404
    assert is_nil(TicketVisibility.actor())
  end

  @tag :visibility_control
  test "widget guest grant cannot bypass a signed-in agent's restriction", c do
    Escalated.Test.GuestAccessHelpers.configure()

    ticket =
      Escalated.repo().update!(Changeset.change(c.hidden, guest_email: "guest@example.test"))

    {:ok, result} =
      Escalated.repo().transaction(fn ->
        Escalated.Services.GuestAccess.issue(ticket, "ticket", ticket.guest_email)
      end)

    token = result["guest_access_token"]

    assert request(:get, "/support/widget/tickets/#{ticket.reference}", @agent, [
             {"x-guest-token", token}
           ]).status == 404

    assert request(:get, "/support/widget/tickets/#{ticket.reference}", nil, [
             {"x-guest-token", token}
           ]).status == 200
  end

  @tag :visibility_control
  test "channels check both joins and delivery after membership revocation", c do
    alias Escalated.Channels.TicketChannel
    socket = %Phoenix.Socket{assigns: %{current_user: @agent}}
    assert {:error, _} = TicketChannel.join("escalated:ticket:#{c.hidden.id}", %{}, socket)
    assert {:ok, joined} = TicketChannel.join("escalated:ticket:#{c.allowed.id}", %{}, socket)
    Escalated.repo().delete!(c.member)

    assert {:stop, :normal, _} =
             TicketChannel.handle_info(
               %{event: "ticket:status_changed", payload: %{ticket_id: c.allowed.id}},
               joined
             )
  end

  @tag :visibility_control
  test "broadcast queues skip inaccessible events", c do
    alias Escalated.Channels.TicketChannel

    socket = %Phoenix.Socket{
      assigns: %{current_user: @agent},
      joined: true,
      transport_pid: self(),
      serializer: Phoenix.Socket.V2.JSONSerializer,
      topic: "escalated:tickets"
    }

    assert {:ok, joined} = TicketChannel.join("escalated:tickets", %{}, socket)

    assert {:noreply, _} =
             TicketChannel.handle_info(
               %{event: "ticket:status_changed", payload: %{ticket_id: c.hidden.id}},
               joined
             )

    refute_receive {:socket_push, _, _}

    assert {:noreply, _} =
             TicketChannel.handle_info(
               %{event: "ticket:status_changed", payload: %{ticket_id: c.allowed.id}},
               joined
             )

    assert_receive {:socket_push, _, _}
  end

  defp request(method, path, user \\ @agent, headers \\ []) do
    base = conn(method, path) |> init_test_session(%{}) |> assign(:current_user, user)

    version =
      base
      |> Inertia.Plug.call(Inertia.Plug.init([]))
      |> Map.fetch!(:private)
      |> Map.fetch!(:inertia_version)
      |> to_string()

    headers = [
      {"x-inertia", "true"},
      {"x-inertia-version", version},
      {"accept", "application/json"} | headers
    ]

    Enum.reduce(headers, base, fn {key, value}, acc -> put_req_header(acc, key, value) end)
    |> Router.call(Router.init([]))
  end
end
