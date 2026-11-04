defmodule Escalated.Controllers.AgentInboxPropsTest do
  @moduledoc """
  The agent panel's optional `inbox` and `queue` props, and the list filters
  its rail, views and stat strip link to (shared frontend
  docs/agent-panel.md, after escalated-laravel's `AgentInboxPropsTest`).

  Every number here must be what the agent would get by opening the list it
  labels, so the tests check counts against the list and against visibility.
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{Department, DepartmentAgent, Reply, SavedView, Ticket}

  @built_in ~w(urgent sla_at_risk waiting_on_me waiting_on_customer recently_updated)
  @index "/support/agent/tickets"

  defp repo, do: Escalated.repo()

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp minutes(n), do: DateTime.add(now(), n * 60, :second)

  defp ticket!(attrs \\ %{}) do
    base = %Ticket{
      subject: "Ticket",
      description: "Body",
      status: "open",
      priority: "low",
      reference: "ESC-#{System.unique_integer([:positive])}"
    }

    repo().insert!(struct(base, attrs))
  end

  defp index(user, query \\ "") do
    visit(:get, @index <> query, user) |> page!("Escalated/Agent/TicketIndex")
  end

  defp total(user, filters) do
    index(user, "?" <> URI.encode_query(filters))["tickets"]["total"]
  end

  setup do
    agent = host_user!(%{name: "Al Agent", is_agent: true})
    other = host_user!(%{name: "Oz Other", is_agent: true})
    %{agent: agent, other: other}
  end

  test "sends inbox counts, built-in views, stats and the queue on the ticket list", ctx do
    me = ctx.agent.id
    ticket!(%{assigned_to: me, priority: "urgent"})
    ticket!(%{assigned_to: me, status: "waiting_on_customer"})
    ticket!(%{assigned_to: me, status: "resolved", resolved_at: now()})
    ticket!(%{assigned_to: me, status: "resolved", resolved_at: minutes(-2 * 24 * 60)})
    ticket!(%{assigned_to: me, status: "snoozed", snoozed_until: minutes(24 * 60)})
    ticket!()
    ticket!(%{status: "closed", closed_at: now()})
    ticket!(%{assigned_to: ctx.other.id})

    props = index(ctx.agent)
    inbox = props["inbox"]

    assert Map.keys(inbox) |> Enum.sort() == ~w(counts stats views)
    # Unresolved, unsnoozed tickets in each queue.
    assert inbox["counts"] == %{"mine" => 2, "unassigned" => 1, "all" => 4}
    assert Enum.map(inbox["views"], & &1["id"]) == @built_in
    assert Map.keys(hd(inbox["views"])) |> Enum.sort() == ~w(count filters id name)

    assert hd(inbox["views"]) == %{
             "id" => "urgent",
             "name" => "Urgent",
             "count" => 1,
             "filters" => %{"priority" => "urgent", "open" => 1}
           }

    # The "all" queue: three tickets with status open, one urgent, one resolved today.
    assert inbox["stats"] == %{
             "open" => 3,
             "urgent" => 1,
             "sla_at_risk" => 0,
             "resolved_today" => 1
           }

    assert props["queue"] == %{"key" => "all", "title" => "All tickets"}

    views = Map.new(inbox["views"], &{&1["id"], &1})
    assert views["waiting_on_customer"]["count"] == 1

    assert views["waiting_on_customer"]["filters"] == %{
             "assigned_to" => me,
             "status" => "waiting_on_customer"
           }

    assert views["waiting_on_me"]["filters"] == %{
             "assigned_to" => me,
             "status" => "waiting_on_agent"
           }

    assert views["sla_at_risk"]["filters"] == %{"sla_at_risk" => 1}

    assert views["recently_updated"]["filters"] == %{
             "open" => 1,
             "updated_within_hours" => 24,
             "sort_by" => "updated_at"
           }

    assert views["recently_updated"]["count"] == 4
  end

  for {name, query, key, title, stats} <- [
        {"mine", "?assigned_to={me}", "mine", "My inbox", [1, 1, 0, 1]},
        {"mine, by alias", "?assigned=me", "mine", "My inbox", [1, 1, 0, 1]},
        {"mine, by assigned_to=me", "?assigned_to=me", "mine", "My inbox", [1, 1, 0, 1]},
        {"mine with a stat tile on", "?assigned_to={me}&priority=urgent", "mine", "My inbox",
         [1, 1, 0, 1]},
        {"unassigned", "?unassigned=1", "unassigned", "Unassigned", [2, 1, 0, 1]},
        {"all", "", "all", "All tickets", [3, 2, 0, 2]},
        {"a built-in view by its filters", "?priority=urgent&open=1", "view:urgent", "Urgent",
         [2, 2, 0, 0]},
        {"a built-in view by id", "?view=urgent", "view:urgent", "Urgent", [2, 2, 0, 0]}
      ] do
    test "names and scopes the queue: #{name}", ctx do
      me = ctx.agent.id
      ticket!(%{assigned_to: me, priority: "urgent"})
      ticket!(%{assigned_to: me, status: "resolved", resolved_at: now()})
      ticket!()
      ticket!(%{status: "resolved", resolved_at: now()})
      ticket!(%{priority: "urgent"})

      [open, urgent, risk, resolved] = unquote(stats)
      props = index(ctx.agent, String.replace(unquote(query), "{me}", to_string(me)))

      assert props["queue"] == %{"key" => unquote(key), "title" => unquote(title)}

      assert props["inbox"]["stats"] == %{
               "open" => open,
               "urgent" => urgent,
               "sla_at_risk" => risk,
               "resolved_today" => resolved
             }
    end
  end

  test "lists the agent's own and shared saved views with counts, but not other agents' private views",
       ctx do
    mine = saved_view!(ctx.agent, "High priority", %{"priority" => "high"}, 1)
    shared = saved_view!(ctx.other, "Waiting", %{"status" => "waiting_on_agent"}, 2, true)
    saved_view!(ctx.other, "Private", %{"priority" => "low"}, 0)

    ticket!(%{priority: "high"})
    ticket!(%{priority: "high"})
    ticket!(%{priority: "high", status: "closed", closed_at: now()})
    ticket!(%{status: "waiting_on_agent"})

    saved =
      index(ctx.agent)["inbox"]["views"]
      |> Enum.reject(&(&1["id"] in @built_in))

    assert saved == [
             %{
               "id" => mine.id,
               "name" => "High priority",
               "count" => 2,
               "filters" => %{"priority" => "high"}
             },
             %{
               "id" => shared.id,
               "name" => "Waiting",
               "count" => 1,
               "filters" => %{"status" => "waiting_on_agent"}
             }
           ]
  end

  for by <- ["id", "filters"] do
    test "selects a saved view as the queue by #{by}, and filters the list with it", ctx do
      view = saved_view!(ctx.agent, "High priority", %{"priority" => "high"}, 1)
      high = ticket!(%{priority: "high"})
      ticket!(%{priority: "low"})

      query = if unquote(by) == "id", do: "?view=#{view.id}", else: "?priority=high"
      props = index(ctx.agent, query)

      assert props["queue"] == %{"key" => "view:#{view.id}", "title" => "High priority"}
      assert Enum.map(props["tickets"]["data"], & &1["id"]) == [high.id]
    end
  end

  test "does not let an agent select another agent's private view", ctx do
    private = saved_view!(ctx.other, "Private", %{"priority" => "high"}, 1)
    ticket!(%{priority: "high"})
    ticket!(%{priority: "low"})

    props = index(ctx.agent, "?view=#{private.id}")

    assert props["queue"] == %{"key" => "all", "title" => "All tickets"}
    assert props["tickets"]["total"] == 2
  end

  test "gives every built-in view the count its own list shows", ctx do
    me = ctx.agent.id
    ticket!(%{assigned_to: me, priority: "urgent"})
    ticket!(%{priority: "urgent", status: "closed", closed_at: now()})
    ticket!(%{assigned_to: me, status: "waiting_on_agent"})
    ticket!(%{assigned_to: me, status: "waiting_on_customer"})
    ticket!(%{sla_breached: true})
    ticket!(%{sla_resolution_due_at: minutes(30)})
    ticket!(%{updated_at: minutes(-3 * 24 * 60)})

    views = index(ctx.agent)["inbox"]["views"]

    for view <- views do
      shown = total(ctx.agent, view["filters"])

      assert view["count"] == shown,
             "view #{view["id"]} counts #{view["count"]} but its list shows #{shown}"
    end

    assert Map.new(views, &{&1["id"], &1["count"]}) == %{
             "urgent" => 1,
             "sla_at_risk" => 2,
             "waiting_on_me" => 1,
             "waiting_on_customer" => 1,
             "recently_updated" => 5
           }
  end

  describe "with department visibility" do
    setup do
      Application.put_env(:escalated, :visibility, :department)
      Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))

      on_exit(fn ->
        Application.delete_env(:escalated, :visibility)
        Application.delete_env(:escalated, :agent_check)
      end)
    end

    test "counts only tickets the agent may see", ctx do
      support = repo().insert!(Department.changeset(%Department{}, %{name: "Support"}))
      billing = repo().insert!(Department.changeset(%Department{}, %{name: "Billing"}))
      repo().insert!(%DepartmentAgent{department_id: support.id, agent_id: ctx.agent.id})

      ticket!(%{department_id: support.id, assigned_to: ctx.agent.id, priority: "urgent"})
      ticket!(%{department_id: support.id})
      ticket!(%{department_id: billing.id})
      ticket!(%{department_id: billing.id, priority: "urgent"})
      ticket!(%{department_id: billing.id, status: "resolved", resolved_at: now()})

      inbox = index(ctx.agent)["inbox"]

      assert inbox["counts"] == %{"mine" => 1, "unassigned" => 1, "all" => 2}

      assert inbox["stats"] == %{
               "open" => 2,
               "urgent" => 1,
               "sla_at_risk" => 0,
               "resolved_today" => 0
             }

      assert Enum.find(inbox["views"], &(&1["id"] == "urgent"))["count"] == 1
    end
  end

  test "filters the list to tickets whose SLA is breached or due within the hour", ctx do
    breached = ticket!(%{sla_breached: true})
    response_due = ticket!(%{sla_first_response_due_at: minutes(20)})
    resolution_due = ticket!(%{sla_resolution_due_at: minutes(50)})
    ticket!(%{sla_first_response_due_at: minutes(20), first_response_at: minutes(-1)})
    ticket!(%{sla_resolution_due_at: minutes(180)})
    ticket!(%{sla_breached: true, status: "resolved", resolved_at: now()})
    ticket!()

    props = index(ctx.agent, "?sla_at_risk=1")
    ids = props["tickets"]["data"] |> Enum.map(& &1["id"]) |> Enum.sort()

    assert ids == Enum.sort([breached.id, response_due.id, resolution_due.id])
    assert props["inbox"]["stats"]["sla_at_risk"] == 3
  end

  test "filters the list to tickets resolved today", ctx do
    start_of_day = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
    today = ticket!(%{status: "resolved", resolved_at: DateTime.add(start_of_day, 60, :second)})
    ticket!(%{status: "resolved", resolved_at: DateTime.add(start_of_day, -24 * 3600, :second)})
    ticket!()

    props = index(ctx.agent, "?status=resolved&resolved_today=1")

    assert Enum.map(props["tickets"]["data"], & &1["id"]) == [today.id]
  end

  test "filters the list to open tickets and to recently updated ones", ctx do
    fresh = ticket!()
    ticket!(%{updated_at: minutes(-3 * 24 * 60)})
    ticket!(%{status: "closed", closed_at: now()})
    ticket!(%{status: "snoozed", snoozed_until: minutes(60)})

    assert index(ctx.agent, "?open=1")["tickets"]["total"] == 2

    props = index(ctx.agent, "?open=1&updated_within_hours=24")
    assert Enum.map(props["tickets"]["data"], & &1["id"]) == [fresh.id]
  end

  test "sorts the list by updated_at when asked", ctx do
    older = ticket!(%{updated_at: minutes(-120)})
    newer = ticket!(%{updated_at: minutes(-5)})
    oldest = ticket!(%{updated_at: minutes(-600)})

    ids = index(ctx.agent, "?sort_by=updated_at")["tickets"]["data"] |> Enum.map(& &1["id"])
    assert ids == [newer.id, older.id, oldest.id]
  end

  for {name, query, field} <- [
        {"sla_at_risk", "sla_at_risk=soon", "sla_at_risk"},
        {"resolved_today", "resolved_today=maybe", "resolved_today"},
        {"open", "open=perhaps", "open"},
        {"updated_within_hours zero", "updated_within_hours=0", "updated_within_hours"},
        {"updated_within_hours text", "updated_within_hours=a+day", "updated_within_hours"},
        {"updated_within_hours too large", "updated_within_hours=8761", "updated_within_hours"}
      ] do
    test "rejects a malformed #{name}", ctx do
      # escalated-laravel's $request->validate(): a JSON client gets a 422 ...
      conn =
        :get
        |> conn(@index <> "?" <> unquote(query))
        |> put_req_header("accept", "application/json")
        |> init_test_session(%{})
        |> assign(:current_user, ctx.agent)
        |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))

      assert conn.status == 422
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body["errors"], unquote(field))
      assert is_binary(body["message"])

      # ... an Inertia visit and a plain browser visit go back with the errors,
      # never a raw 422 (which the Inertia client shows as an error modal).
      inertia = visit(:get, @index <> "?" <> unquote(query), ctx.agent)
      assert inertia.status == 302

      browser =
        :get
        |> conn(@index <> "?" <> unquote(query))
        |> put_req_header("accept", "text/html")
        |> put_req_header("referer", "http://www.example.com" <> @index <> "?assigned=me")
        |> init_test_session(%{})
        |> assign(:current_user, ctx.agent)
        |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))

      assert browser.status == 302
      assert get_resp_header(browser, "location") == [@index <> "?assigned=me"]
    end
  end

  test "previews the latest customer-visible message, never an internal note", ctx do
    ticket = ticket!()
    answered_at = minutes(-5)

    repo().insert!(%Reply{
      ticket_id: ticket.id,
      body: "Customer-visible answer",
      author_id: ctx.agent.id,
      is_internal: false,
      inserted_at: answered_at
    })

    repo().insert!(%Reply{
      ticket_id: ticket.id,
      body: "Secret internal note",
      author_id: ctx.agent.id,
      is_internal: true,
      inserted_at: now()
    })

    [row] = index(ctx.agent)["tickets"]["data"]

    assert row["latest_reply"]["body"] == "Customer-visible answer"
    assert row["latest_reply"]["author"]["name"] == "Al Agent"
    assert row["last_reply_at"] == DateTime.to_iso8601(answered_at)
    # Escalated tracks no per-agent read state or customer presence.
    refute Map.has_key?(row, "is_unread")
    refute Map.has_key?(row, "requester_online")
  end

  test "sends inbox and the queue the agent last opened on the ticket page", ctx do
    ticket = ticket!(%{assigned_to: ctx.agent.id})
    ticket!()
    show = "/support/agent/tickets/#{ticket.reference}"

    props = visit(:get, show, ctx.agent) |> page!("Escalated/Agent/TicketShow")
    assert props["queue"] == %{"key" => "all", "title" => "All tickets"}
    assert props["inbox"]["counts"] == %{"mine" => 1, "unassigned" => 1, "all" => 2}
    assert Map.keys(props["inbox"]) |> Enum.sort() == ~w(counts stats views)

    list = visit(:get, @index <> "?assigned_to=#{ctx.agent.id}", ctx.agent)
    assert list.status == 200

    props =
      :get
      |> conn(show)
      |> init_test_session(list.private[:plug_session] || %{})
      |> assign(:current_user, ctx.agent)
      |> put_req_header("x-inertia", "true")
      |> put_req_header("x-inertia-version", inertia_version())
      |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
      |> page!("Escalated/Agent/TicketShow")

    assert props["queue"] == %{"key" => "mine", "title" => "My inbox"}

    assert props["inbox"]["stats"] == %{
             "open" => 1,
             "urgent" => 0,
             "sla_at_risk" => 0,
             "resolved_today" => 0
           }
  end

  test "builds the inbox with a bounded number of queries", ctx do
    for i <- 1..3, do: saved_view!(ctx.agent, "View #{i}", %{"priority" => "high"}, i)
    for _ <- 1..3, do: ticket!()

    first = count_ticket_queries(fn -> index(ctx.agent) end)
    for _ <- 1..6, do: ticket!()
    second = count_ticket_queries(fn -> index(ctx.agent) end)

    # The number of count queries does not grow with the number of tickets.
    assert first.counts == second.counts
    assert first.counts == 3 + 5 + 3 + 4
  end

  defp saved_view!(user, name, filters, position, shared \\ false) do
    repo().insert!(
      SavedView.changeset(%SavedView{}, %{
        user_id: user.id,
        name: name,
        filters: filters,
        position: position,
        is_shared: shared
      })
    )
  end

  # Counts `SELECT count(...)` queries on the tickets table during `fun`.
  defp count_ticket_queries(fun) do
    parent = self()
    ref = make_ref()
    handler = "agent-inbox-#{inspect(ref)}"
    prefix = Escalated.repo().config()[:telemetry_prefix]

    :telemetry.attach(
      handler,
      prefix ++ [:query],
      fn _event, _measurements, %{query: sql}, _ -> send(parent, {ref, sql}) end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    sql = drain(ref, [])
    tickets = Escalated.table_name("tickets")

    %{
      counts: Enum.count(sql, &(&1 =~ ~r/count\(/i and &1 =~ ~r/FROM [`"]?#{tickets}[`"]?/i))
    }
  end

  defp drain(ref, acc) do
    receive do
      {^ref, sql} -> drain(ref, [sql | acc])
    after
      0 -> acc
    end
  end
end
