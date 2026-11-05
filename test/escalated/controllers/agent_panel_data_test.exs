defmodule Escalated.Controllers.AgentPanelDataTest do
  @moduledoc """
  The agent panel's data (escalated-developer-context ADR
  2026-11-05-agent-panel-data, after escalated-laravel #292-#296): agent
  status, knowledge-base search, unread markers, customer presence and the
  agents' in-app notifications.
  """
  use Escalated.PageCase

  import Ecto.Query

  alias Escalated.AgentPanel

  alias Escalated.Schemas.{
    AgentNotification,
    AgentProfile,
    Article,
    ArticleCategory,
    CustomerPresence,
    Department,
    DepartmentAgent,
    Permission,
    Role,
    RolePermission,
    Ticket,
    TicketRead
  }

  alias Escalated.Services.{AssignmentService, Followers, TicketService}
  alias Escalated.Test.{Router, SharedPropsRouter}

  @pubsub Escalated.Test.AgentPanelPubSub

  defp repo, do: Escalated.repo()

  setup do
    agent = host_user!(%{name: "Al Agent", is_agent: true})
    other = host_user!(%{name: "Oz Other", is_agent: true})
    customer = host_user!(%{name: "Cy Customer"})

    on_exit(fn ->
      for key <- [
            :knowledge_base_enabled,
            :agent_notifications,
            :presence_online_window_seconds,
            :visibility,
            :agent_check,
            :access,
            :broadcasting_enabled,
            :pubsub_server
          ],
          do: Application.delete_env(:escalated, key)
    end)

    %{agent: agent, other: other, customer: customer}
  end

  defp ticket!(ctx, attrs \\ %{}) do
    {:ok, ticket} =
      TicketService.create(
        Map.merge(
          %{
            subject: "Printer on fire",
            description: "Help",
            requester_id: ctx.customer.id,
            requester_type: "user"
          },
          attrs
        )
      )

    ticket
  end

  defp api(method, path, user, body \\ nil, router \\ Router) do
    base =
      if body,
        do:
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json"),
        else: conn(method, path)

    base
    |> init_test_session(%{})
    |> put_req_header("accept", "application/json")
    |> then(fn conn -> if user, do: assign(conn, :current_user, user), else: conn end)
    |> router.call(router.init([]))
  end

  defp json!(conn, status \\ 200) do
    assert conn.status == status, "expected #{status}, got #{conn.status}: #{conn.resp_body}"
    Jason.decode!(conn.resp_body)
  end

  defp shared(path, user) do
    conn(:get, path)
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> SharedPropsRouter.call(SharedPropsRouter.init([]))
    |> then(fn conn ->
      assert conn.status == 200, "#{path} answered #{conn.status}: #{conn.resp_body}"
      Jason.decode!(conn.resp_body)["props"]["escalated"]
    end)
  end

  defp rows(user) do
    visit(:get, "/support/agent/tickets", user)
    |> page!("Escalated/Agent/TicketIndex")
    |> Map.fetch!("tickets")
    |> Map.fetch!("data")
    |> Map.new(&{&1["reference"], &1})
  end

  defp open!(ticket, user) do
    visit(:get, "/support/agent/tickets/#{ticket.reference}", user)
    |> page!("Escalated/Agent/TicketShow")
  end

  defp ago(seconds),
    do: DateTime.utc_now() |> DateTime.add(-seconds, :second) |> DateTime.truncate(:second)

  # Reads are kept to the second, so a reply in the same second as a read is
  # not after it; backdate the activity and the read as earlier visits would.
  defp backdate_read!(user, ticket) do
    from(r in TicketRead, where: r.ticket_id == ^ticket.id and r.user_id == ^to_string(user.id))
    |> repo().update_all(set: [last_read_at: ago(60)])

    from(t in Ticket, where: t.id == ^ticket.id)
    |> repo().update_all(set: [last_customer_activity_at: ago(120)])
  end

  defp customer_reply!(ctx, ticket),
    do:
      {:ok, _} = TicketService.reply(ticket, %{body: "Still broken", author_id: ctx.customer.id})

  defp notifications(user),
    do: repo().all(from(n in AgentNotification, where: n.user_id == ^to_string(user.id)))

  # --- Agent status -------------------------------------------------------

  describe "agent status" do
    test "an agent sets their status and every staff page shares it", ctx do
      assert shared("/support/agent/tickets", ctx.agent)["agent_status"] == "offline"

      assert shared("/support/agent/tickets", ctx.agent)["agent_statuses"] ==
               ~w(online away offline)

      body = api(:put, "/support/agent/status", ctx.agent, %{status: "away"}) |> json!()
      assert body["agent_status"] == "away"

      assert repo().one(from(p in AgentProfile, where: p.user_id == ^ctx.agent.id)).chat_status ==
               "away"

      assert shared("/support/agent/tickets", ctx.agent)["agent_status"] == "away"
      assert api(:post, "/support/agent/status", ctx.agent, %{status: "online"}) |> json!()
      assert AgentPanel.status(ctx.agent) == "online"
    end

    test "an invalid status is refused", ctx do
      body = api(:put, "/support/agent/status", ctx.agent, %{status: "busy"}) |> json!(422)
      assert Map.has_key?(body["errors"], "status")
      assert AgentPanel.status(ctx.agent) == "offline"
    end

    test "an Inertia visit goes back", ctx do
      conn =
        conn(:put, "/support/agent/status", Jason.encode!(%{status: "away"}))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("referer", "http://localhost/support/agent/tickets?page=2")
        |> init_test_session(%{})
        |> assign(:current_user, ctx.agent)
        |> put_req_header("x-inertia", "true")
        |> put_req_header("x-inertia-version", inertia_version())
        |> Router.call(Router.init([]))

      assert conn.status in [302, 303]
      assert location(conn) == "/support/agent/tickets?page=2"
    end

    test "customers have no status and cannot set one", ctx do
      refute api(:put, "/support/agent/status", ctx.customer, %{status: "away"}).status == 200
      props = shared("/support/tickets", ctx.customer)
      refute Map.has_key?(props, "agent_status")
      refute Map.has_key?(props, "notifications")
    end
  end

  # --- Knowledge base search ------------------------------------------------

  defp article!(attrs) do
    repo().insert!(
      struct(
        %Article{
          status: "published",
          body: "Body",
          slug: "a-#{System.unique_integer([:positive])}"
        },
        attrs
      )
    )
  end

  describe "knowledge base search" do
    setup do
      Application.put_env(:escalated, :knowledge_base_enabled, true)
      :ok
    end

    test "answers published articles, title matches first, newest next", ctx do
      category = repo().insert!(%ArticleCategory{name: "Accounts", slug: "accounts"})

      body_match =
        article!(%{
          title: "Account basics",
          body: "<p>To reset your password open   Settings.</p>",
          slug: "basics",
          category_id: category.id,
          updated_at: ago(10)
        })

      old_title = article!(%{title: "Password rules", slug: "rules", updated_at: ago(500)})
      new_title = article!(%{title: "Password reset", slug: "reset", updated_at: ago(100)})
      article!(%{title: "Password draft", status: "draft"})

      data =
        api(:get, "/support/agent/kb/search?q=password", ctx.agent)
        |> json!()
        |> Map.fetch!("data")

      assert Enum.map(data, & &1["id"]) == [new_title.id, old_title.id, body_match.id]
      item = List.last(data)
      assert Map.keys(item) |> Enum.sort() == ~w(category excerpt id title updated_at url)
      assert item["category"] == %{"id" => category.id, "name" => "Accounts"}
      assert item["excerpt"] == "To reset your password open Settings."
      assert item["url"] == "http://www.example.com/support/kb/basics"
      assert hd(data)["category"] == nil
    end

    test "is case-insensitive and takes % and _ literally", ctx do
      percent = article!(%{title: "Save 50% today"})
      article!(%{title: "Save 50 dollars today"})
      underscore = article!(%{title: "The snake_case guide"})
      article!(%{title: "The snakeXcase guide"})

      search = fn q ->
        api(:get, "/support/agent/kb/search?" <> URI.encode_query(%{q: q}), ctx.agent)
        |> json!()
        |> Map.fetch!("data")
        |> Enum.map(& &1["id"])
      end

      assert search.("50%") == [percent.id]
      assert search.("SNAKE_CASE") == [underscore.id]
    end

    test "validates q and limit", ctx do
      for {query, field} <- [
            {"q=a", "q"},
            {"q=" <> String.duplicate("a", 201), "q"},
            {"q=abc&limit=0", "limit"},
            {"q=abc&limit=21", "limit"}
          ] do
        body = api(:get, "/support/agent/kb/search?" <> query, ctx.agent) |> json!(422)
        assert Map.has_key?(body["errors"], field), query
      end

      for n <- 1..3, do: article!(%{title: "Limit #{n}"})

      assert api(:get, "/support/agent/kb/search?q=limit&limit=2", ctx.agent)
             |> json!()
             |> Map.fetch!("data")
             |> length() == 2
    end

    test "is 404 while the knowledge base is off", ctx do
      Application.put_env(:escalated, :knowledge_base_enabled, false)
      assert api(:get, "/support/agent/kb/search?q=password", ctx.agent).status == 404
    end
  end

  # --- Roles & permissions -----------------------------------------------------

  describe "roles and permissions" do
    setup ctx do
      {:ok, _} = Escalated.Tenancy.Provisioner.seed()
      slug = "panel-#{System.unique_integer([:positive])}"
      role = repo().insert!(Role.changeset(%Role{}, %{name: slug, slug: slug}))

      for permission <- repo().all(from(p in Permission, where: p.slug in ["ticket.view"])) do
        repo().insert!(%RolePermission{role_id: role.id, permission_id: permission.id})
      end

      {:ok, _} = Escalated.Roles.assign(ctx.agent.id, slug)
      Application.put_env(:escalated, :access, roles_permissions: true)
      Application.put_env(:escalated, :knowledge_base_enabled, true)
      :ok
    end

    test "KB search needs kb.view; status, read markers and notifications need nothing more",
         ctx do
      ticket = ticket!(ctx)
      assert api(:get, "/support/agent/kb/search?q=password", ctx.agent).status == 403
      assert api(:put, "/support/agent/status", ctx.agent, %{status: "away"}) |> json!()
      assert api(:get, "/support/agent/notifications", ctx.agent) |> json!()
      assert api(:post, "/support/agent/notifications/read-all", ctx.agent) |> json!()

      assert api(:post, "/support/agent/tickets/#{ticket.reference}/unread", ctx.agent)
             |> json!() == %{"is_unread" => true}
    end
  end

  # --- Unread markers -----------------------------------------------------------

  describe "unread markers" do
    test "a new ticket is unread until the agent opens it", ctx do
      ticket = ticket!(ctx)
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == true

      assert open!(ticket, ctx.agent)["ticket"]["is_unread"] == false
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == false
      # Per agent.
      assert rows(ctx.other)[ticket.reference]["is_unread"] == true
    end

    test "customer replies make it unread again; agents' replies and notes do not", ctx do
      ticket = ticket!(ctx)
      open!(ticket, ctx.agent)
      backdate_read!(ctx.agent, ticket)

      {:ok, _} = TicketService.reply(ticket, %{body: "On it", author_id: ctx.other.id})

      {:ok, _} =
        TicketService.reply(ticket, %{body: "Note", author_id: ctx.other.id, is_internal: true})

      # A workflow's canned reply.
      {:ok, _} = TicketService.reply(ticket, %{body: "Thanks!"}, author: :system)
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == false

      customer_reply!(ctx, ticket)
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == true

      # A guest or inbound email (no author) is the customer side too.
      open!(ticket, ctx.agent)
      backdate_read!(ctx.agent, ticket)
      {:ok, _} = TicketService.reply(ticket, %{body: "By email"})
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == true
    end

    test "imported tickets are not customer activity", ctx do
      {:ok, ticket} = Escalated.Import.Context.suppress(fn -> {:ok, ticket!(ctx)} end)
      assert repo().get(Ticket, ticket.id).last_customer_activity_at == nil
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == false
    end

    test "the read and unread routes answer is_unread", ctx do
      ticket = ticket!(ctx)
      path = "/support/agent/tickets/#{ticket.reference}"

      assert api(:post, path <> "/read", ctx.agent) |> json!() == %{"is_unread" => false}
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == false
      assert api(:post, path <> "/unread", ctx.agent) |> json!() == %{"is_unread" => true}
      assert rows(ctx.agent)[ticket.reference]["is_unread"] == true
      assert api(:post, "/support/agent/tickets/NOPE-1/read", ctx.agent).status == 404
    end

    test "bulk mark_read and mark_unread", ctx do
      a = ticket!(ctx)
      b = ticket!(ctx)

      visit(:post, "/support/agent/tickets/bulk", ctx.agent, %{
        ticket_ids: [a.id, b.id],
        action: "mark_read"
      })

      rows = rows(ctx.agent)
      assert [rows[a.reference]["is_unread"], rows[b.reference]["is_unread"]] == [false, false]

      visit(:post, "/support/agent/tickets/bulk", ctx.agent, %{
        ticket_ids: [a.id],
        action: "mark_unread"
      })

      rows = rows(ctx.agent)
      assert [rows[a.reference]["is_unread"], rows[b.reference]["is_unread"]] == [true, false]
    end

    test "inbox.unread counts unread open tickets per queue", ctx do
      mine = ticket!(ctx, %{assigned_to: ctx.agent.id})
      ticket!(ctx, %{assigned_to: ctx.agent.id})
      unassigned = ticket!(ctx)
      resolved = ticket!(ctx)
      {:ok, _} = TicketService.transition_status(resolved, "resolved")
      open!(mine, ctx.agent)
      open!(unassigned, ctx.agent)

      inbox =
        visit(:get, "/support/agent/tickets", ctx.agent)
        |> page!("Escalated/Agent/TicketIndex")
        |> Map.fetch!("inbox")

      assert inbox["unread"] == %{"mine" => 1, "unassigned" => 0, "all" => 1}
    end

    test "only tickets the agent may see are counted and marked", ctx do
      Application.put_env(:escalated, :visibility, :department)
      Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
      sales = repo().insert!(%Department{name: "Sales", slug: "sales"})
      support = repo().insert!(%Department{name: "Support", slug: "support"})
      repo().insert!(%DepartmentAgent{department_id: support.id, agent_id: ctx.agent.id})

      visible = ticket!(ctx, %{department_id: support.id})
      hidden = ticket!(ctx, %{department_id: sales.id})

      inbox =
        visit(:get, "/support/agent/tickets", ctx.agent)
        |> page!("Escalated/Agent/TicketIndex")
        |> Map.fetch!("inbox")

      assert inbox["unread"]["all"] == 1
      assert Map.keys(rows(ctx.agent)) == [visible.reference]

      refute api(:post, "/support/agent/tickets/#{hidden.reference}/read", ctx.agent).status ==
               200

      assert repo().all(from(r in TicketRead, where: r.ticket_id == ^hidden.id)) == []
    end
  end

  # --- Customer presence ------------------------------------------------------------

  describe "customer presence" do
    test "a customer on the portal shows as online on agent pages only", ctx do
      ticket = ticket!(ctx)
      row = rows(ctx.agent)[ticket.reference]
      assert [row["requester_online"], row["requester_last_seen_at"]] == [false, nil]

      visit(:get, "/support/tickets", ctx.customer)

      row = rows(ctx.agent)[ticket.reference]
      assert row["requester_online"] == true
      assert is_binary(row["requester_last_seen_at"])
      assert open!(ticket, ctx.agent)["ticket"]["requester_online"] == true

      customer_page = visit(:get, "/support/tickets/#{ticket.reference}", ctx.customer)
      refute customer_page.resp_body =~ "requester_online"
      refute customer_page.resp_body =~ "requester_last_seen_at"
      refute customer_page.resp_body =~ "is_unread"
    end

    test "recording is throttled to every 30 seconds", ctx do
      visit(:get, "/support/tickets", ctx.customer)
      seen = fn -> repo().one!(from(p in CustomerPresence, select: p.last_seen_at)) end

      repo().update_all(CustomerPresence, set: [last_seen_at: ago(10)])
      recent = seen.()
      visit(:get, "/support/tickets", ctx.customer)
      assert seen.() == recent

      repo().update_all(CustomerPresence, set: [last_seen_at: ago(40)])
      visit(:get, "/support/tickets", ctx.customer)
      assert DateTime.diff(seen.(), ago(0)) in -2..0
      assert repo().aggregate(CustomerPresence, :count) == 1
    end

    test "a customer last seen outside the window is offline", ctx do
      Application.put_env(:escalated, :presence_online_window_seconds, 60)
      ticket = ticket!(ctx)
      visit(:get, "/support/tickets", ctx.customer)
      repo().update_all(CustomerPresence, set: [last_seen_at: ago(90)])

      row = rows(ctx.agent)[ticket.reference]
      assert row["requester_online"] == false
      assert is_binary(row["requester_last_seen_at"])
    end

    test "staff browsing the portal are not recorded", ctx do
      visit(:get, "/support/tickets", ctx.agent)
      assert repo().aggregate(CustomerPresence, :count) == 0
    end
  end

  # --- Notifications -----------------------------------------------------------------

  describe "notifications" do
    test "assignment by someone else notifies; assigning yourself does not", ctx do
      ticket = ticket!(ctx)
      {:ok, _} = AssignmentService.assign(ticket, ctx.agent.id, actor_id: ctx.agent.id)
      assert notifications(ctx.agent) == []

      {:ok, _} = AssignmentService.assign(ticket, ctx.agent.id, actor_id: ctx.other.id)
      body = api(:get, "/support/agent/notifications", ctx.agent) |> json!()

      assert body["meta"] == %{
               "current_page" => 1,
               "last_page" => 1,
               "per_page" => 20,
               "total" => 1
             }

      [item] = body["data"]

      assert Map.keys(item) |> Enum.sort() ==
               ~w(body created_at id read_at ticket title type url)

      assert item["type"] == "ticket_assigned"
      assert item["title"] == "#{ticket.reference} was assigned to you"
      assert item["body"] == ticket.subject

      assert item["ticket"] == %{
               "id" => ticket.id,
               "reference" => ticket.reference,
               "subject" => ticket.subject
             }

      assert item["url"] == "/support/agent/tickets/#{ticket.reference}"
      assert item["read_at"] == nil

      assert shared("/support/agent/tickets", ctx.agent)["notifications"] == %{
               "unread_count" => 1
             }
    end

    test "only customer-side replies notify the assignee and followers", ctx do
      ticket = ticket!(ctx, %{assigned_to: ctx.agent.id})
      {:ok, _} = Followers.add_follower(ticket.id, ctx.other.id)

      {:ok, _} = TicketService.reply(ticket, %{body: "Agent reply", author_id: ctx.other.id})

      {:ok, _} =
        TicketService.reply(ticket, %{body: "Note", author_id: ctx.other.id, is_internal: true})

      assert notifications(ctx.agent) == []

      customer_reply!(ctx, ticket)
      assert [%{type: "ticket_reply"}] = notifications(ctx.agent)
      assert [%{type: "ticket_reply"}] = notifications(ctx.other)
    end

    test "mentions, SLA breaches, SLA warnings and chat transfers notify", ctx do
      ticket = ticket!(ctx, %{assigned_to: ctx.agent.id})

      {:ok, _} =
        TicketService.reply(ticket, %{
          body: "Ask @{Al Agent} please",
          author_id: ctx.other.id,
          is_internal: true
        })

      Escalated.Events.emit("sla.warning", %{ticket: ticket})
      Escalated.Events.emit("sla.breached", %{ticket: ticket, breach_type: "resolution"})

      Escalated.Events.emit("chat.transferred", %{
        ticket: ticket,
        chat: %{session_id: 1, from_agent_id: ctx.other.id, to_agent_id: ctx.agent.id}
      })

      items =
        api(:get, "/support/agent/notifications", ctx.agent) |> json!() |> Map.fetch!("data")

      by_type = Map.new(items, &{&1["type"], &1})

      assert Map.keys(by_type) |> Enum.sort() ==
               ~w(chat_transferred mention sla_breached sla_warning)

      assert by_type["sla_breached"]["title"] == "SLA breached on #{ticket.reference}"
      assert by_type["mention"]["title"] == "Oz Other mentioned you in #{ticket.reference}"
    end

    test "a ticket the agent can no longer view is redacted", ctx do
      Application.put_env(:escalated, :visibility, :department)
      Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
      sales = repo().insert!(%Department{name: "Sales", slug: "sales"})
      ticket = ticket!(ctx, %{department_id: sales.id})
      AgentPanel.notify(ctx.agent.id, "ticket_assigned", ticket, %{}, nil)

      [item] =
        api(:get, "/support/agent/notifications", ctx.agent) |> json!() |> Map.fetch!("data")

      assert item["title"] == "A ticket you can no longer view"
      assert [item["body"], item["ticket"], item["url"]] == [nil, nil, nil]
      refute Jason.encode!(item) =~ ticket.subject
    end

    test "read, read-all, the unread filter and paging", ctx do
      ticket = ticket!(ctx)
      for _ <- 1..3, do: AgentPanel.notify(ctx.agent.id, "ticket_assigned", ticket, %{}, nil)
      AgentPanel.notify(ctx.other.id, "ticket_assigned", ticket, %{}, nil)
      [first | _] = notifications(ctx.agent)
      [others] = notifications(ctx.other)

      assert api(:post, "/support/agent/notifications/#{first.id}/read", ctx.agent) |> json!() ==
               %{"unread_count" => 2}

      assert api(:post, "/support/agent/notifications/#{others.id}/read", ctx.agent).status == 404
      assert api(:post, "/support/agent/notifications/not-a-uuid/read", ctx.agent).status == 404

      unread = api(:get, "/support/agent/notifications?unread=1", ctx.agent) |> json!()
      assert unread["meta"]["total"] == 2

      paged = api(:get, "/support/agent/notifications?per_page=2&page=2", ctx.agent) |> json!()

      assert paged["meta"] == %{
               "current_page" => 2,
               "last_page" => 2,
               "per_page" => 2,
               "total" => 3
             }

      assert length(paged["data"]) == 1

      assert api(:get, "/support/agent/notifications?per_page=500", ctx.agent)
             |> json!()
             |> get_in(["meta", "per_page"]) == 50

      assert api(:post, "/support/agent/notifications/read-all", ctx.agent) |> json!() ==
               %{"unread_count" => 0}

      assert AgentPanel.unread_count(ctx.agent) == 0
      assert AgentPanel.unread_count(ctx.other) == 1
    end

    test "each new notification is broadcast on the agent's topic", ctx do
      start_supervised!({Phoenix.PubSub, name: @pubsub})
      Application.put_env(:escalated, :broadcasting_enabled, true)
      Application.put_env(:escalated, :pubsub_server, @pubsub)
      :ok = Phoenix.PubSub.subscribe(@pubsub, "escalated:agent:#{ctx.agent.id}")

      ticket = ticket!(ctx)
      {:ok, _} = AssignmentService.assign(ticket, ctx.agent.id, actor_id: ctx.other.id)

      assert_receive %{event: "notification.created", payload: %{type: "ticket_assigned"} = item}
      assert item.ticket.reference == ticket.reference
    end

    test "switched off, nothing is stored and the routes are 404", ctx do
      Application.put_env(:escalated, :agent_notifications, false)
      ticket = ticket!(ctx)
      {:ok, _} = AssignmentService.assign(ticket, ctx.agent.id, actor_id: ctx.other.id)

      assert notifications(ctx.agent) == []
      assert api(:get, "/support/agent/notifications", ctx.agent).status == 404
      assert api(:post, "/support/agent/notifications/read-all", ctx.agent).status == 404
      refute Map.has_key?(shared("/support/agent/tickets", ctx.agent), "notifications")
    end
  end
end
