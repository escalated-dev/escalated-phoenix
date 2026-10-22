defmodule Escalated.Controllers.TicketPagesTest do
  @moduledoc """
  The core ticket pages, against the props the shared Vue pages read
  (escalated-laravel's Agent, Admin and Customer `TicketController`, the agent
  `DashboardController` and `CustomerTicketPayload`), and the writes those
  pages post.
  """
  use Escalated.PageCase

  require Ecto.Query

  alias Escalated.Schemas.{
    CannedResponse,
    Department,
    Macro,
    Reply,
    SatisfactionRating,
    Tag,
    Ticket,
    TicketFollower
  }

  alias Escalated.Services.TicketService

  @row_keys ~w(id reference subject status priority ticket_type requester assignee department tags
               latest_reply first_response_due_at resolution_due_at sla_first_response_breached
               sla_resolution_breached snoozed_until created_at updated_at)

  @staff_ticket_keys @row_keys ++
                       ~w(description attachments replies pinned_notes activities satisfaction_rating
                          sla_policy subjects channel chat_session_id chat_started_at chat_messages
                          chat_metadata requester_ticket_count related_tickets is_snoozed assigned_to)

  @reply_keys ~w(id body is_internal_note is_pinned author attachments created_at)

  defp repo, do: Escalated.repo()

  setup do
    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})
    agent = host_user!(%{name: "Al Agent", is_agent: true})
    customer = host_user!(%{name: "Cy Customer", email: "cy@example.test"})
    department = repo().insert!(Department.changeset(%Department{}, %{name: "Billing"}))
    tag = repo().insert!(Tag.changeset(%Tag{}, %{name: "vip", color: "#ff0000"}))

    {:ok, ticket} =
      TicketService.create(%{
        subject: "Refund please",
        description: "I was charged twice",
        requester_id: customer.id,
        requester_type: "user",
        department_id: department.id,
        priority: "high"
      })

    {:ok, ticket} =
      Escalated.Services.AssignmentService.assign(ticket, agent.id, actor_id: admin.id)

    TicketService.add_tags(ticket, [tag.id], actor_id: admin.id)

    {:ok, public_reply} =
      TicketService.reply(ticket, %{body: "On it", author_id: agent.id, is_internal: false})

    {:ok, note} =
      TicketService.reply(ticket, %{body: "Secret note", author_id: agent.id, is_internal: true})

    %{
      admin: admin,
      agent: agent,
      customer: customer,
      department: department,
      tag: tag,
      ticket: repo().get!(Ticket, ticket.id),
      public_reply: public_reply,
      note: note
    }
  end

  describe "Escalated/Admin/Tickets/Index" do
    test "sends a paginator of rows plus the filter pickers", ctx do
      repo().insert!(
        CannedResponse.changeset(%CannedResponse{}, %{
          title: "x",
          body: "y",
          created_by: ctx.admin.id
        })
      )

      props =
        visit(:get, "/support/admin/tickets", ctx.admin) |> page!("Escalated/Admin/Tickets/Index")

      assert_keys(props, ~w(tickets filters departments tags agents savedViews))
      [row] = assert_paginator(props["tickets"])
      assert_keys(row, @row_keys, "ticket row")
      assert row["requester"] == %{"name" => "Cy Customer", "email" => "cy@example.test"}
      assert row["assignee"]["name"] == "Al Agent"
      assert row["department"] == %{"id" => ctx.department.id, "name" => "Billing"}
      assert [%{"name" => "vip", "color" => "#ff0000"}] = row["tags"]
      assert row["latest_reply"]["author"]["name"] == "Al Agent"
      assert_keys(hd(props["departments"]), ~w(id name), "department")
      assert_keys(hd(props["tags"]), ~w(id name color), "tag")

      agent_names = Enum.map(props["agents"], & &1["name"])
      assert "Al Agent" in agent_names and "Ada Admin" in agent_names
      refute "Cy Customer" in agent_names
      assert_keys(hd(props["agents"]), ~w(id name email), "agent")
      assert is_list(props["savedViews"])
    end

    test "pages the queue", ctx do
      for n <- 1..3, do: TicketService.create(%{subject: "Extra #{n}", description: "x"})

      props =
        visit(:get, "/support/admin/tickets?per_page=2&page=2", ctx.admin)
        |> page!("Escalated/Admin/Tickets/Index")

      assert props["tickets"]["total"] == 4
      assert props["tickets"]["current_page"] == 2
      assert props["tickets"]["last_page"] == 2
      assert length(props["tickets"]["data"]) == 2
    end
  end

  describe "Escalated/Admin/Tickets/Show" do
    test "puts the thread on the ticket and sends the desk's pickers", ctx do
      repo().insert!(
        Macro.changeset(%Macro{}, %{name: "Close it", actions: [], created_by: ctx.admin.id})
      )

      TicketService.snooze_ticket(ctx.ticket, DateTime.add(DateTime.utc_now(), 3600),
        actor_id: ctx.admin.id
      )

      props =
        visit(:get, "/support/admin/tickets/#{ctx.ticket.reference}", ctx.admin)
        |> page!("Escalated/Admin/Tickets/Show")

      assert_keys(
        props,
        ~w(ticket departments tags cannedResponses agents macros is_following followers_count is_snoozed)
      )

      ticket = assert_keys(props["ticket"], @staff_ticket_keys, "ticket")
      assert length(ticket["replies"]) == 2
      Enum.each(ticket["replies"], &assert_keys(&1, @reply_keys, "reply"))
      assert Enum.any?(ticket["replies"], &(&1["is_internal_note"] == true))
      assert hd(ticket["replies"])["author"]["name"] == "Al Agent"
      assert ticket["activities"] != []

      assert_keys(
        hd(ticket["activities"]),
        ~w(id type description causer properties created_at created_at_human),
        "activity"
      )

      assert ticket["requester"]["name"] == "Cy Customer"
      assert props["is_snoozed"] == true
      assert props["is_following"] == false
      assert props["followers_count"] == 0
      assert [%{"name" => "Close it"}] = props["macros"]
    end

    test "pinned internal notes are listed on the ticket", ctx do
      repo().update!(Reply.changeset(ctx.note, %{is_pinned: true}))

      props =
        visit(:get, "/support/admin/tickets/#{ctx.ticket.reference}", ctx.admin)
        |> page!("Escalated/Admin/Tickets/Show")

      assert [note] = props["ticket"]["pinned_notes"]
      assert_keys(note, ~w(id body author created_at), "pinned note")
      assert note["author"]["name"] == "Al Agent"
    end
  end

  describe "Escalated/Agent/TicketIndex" do
    test "sends a paginator, the filters and the pickers", ctx do
      props =
        visit(:get, "/support/agent/tickets", ctx.agent) |> page!("Escalated/Agent/TicketIndex")

      assert_keys(props, ~w(tickets filters departments tags))
      [row] = assert_paginator(props["tickets"])
      assert_keys(row, @row_keys, "ticket row")
    end
  end

  describe "Escalated/Agent/TicketShow" do
    test "sends the ticket with its thread and the composer's lists", ctx do
      repo().insert!(%TicketFollower{ticket_id: ctx.ticket.id, user_id: to_string(ctx.agent.id)})

      props =
        visit(:get, "/support/agent/tickets/#{ctx.ticket.reference}", ctx.agent)
        |> page!("Escalated/Agent/TicketShow")

      assert_keys(
        props,
        ~w(ticket departments tags cannedResponses macros customActions is_following followers_count)
      )

      assert_keys(props["ticket"], @staff_ticket_keys, "ticket")
      assert props["is_following"] == true
      assert props["followers_count"] == 1
    end
  end

  describe "Escalated/Agent/Dashboard" do
    test "sends the stats, recent tickets, attention lists and performance", ctx do
      props =
        visit(:get, "/support/agent/dashboard", ctx.agent) |> page!("Escalated/Agent/Dashboard")

      assert_keys(props, ~w(stats recentTickets needsAttention myPerformance))

      assert_keys(
        props["stats"],
        ~w(open my_assigned unassigned sla_breached resolved_today),
        "stats"
      )

      assert props["stats"]["open"] == 1
      assert props["stats"]["my_assigned"] == 1
      assert_keys(props["needsAttention"], ~w(sla_breaching unassigned_urgent), "needsAttention")
      assert_keys(props["myPerformance"], ~w(resolved_this_week), "myPerformance")
      [recent] = props["recentTickets"]

      assert_keys(
        recent,
        ~w(id reference subject status priority requester assignee latest_reply),
        "recent ticket"
      )
    end
  end

  describe "customer pages" do
    test "Escalated/Customer/Index sends a paginator and the filters", ctx do
      props = visit(:get, "/support/tickets", ctx.customer) |> page!("Escalated/Customer/Index")

      assert_keys(props, ~w(tickets filters))
      [row] = assert_paginator(props["tickets"])

      assert_keys(
        row,
        ~w(id reference subject status priority created_at updated_at),
        "ticket row"
      )

      refute Map.has_key?(row, "assigned_to")
    end

    test "Escalated/Customer/Show sends the requester-safe payload", ctx do
      repo().insert!(%SatisfactionRating{
        ticket_id: ctx.ticket.id,
        rating: 5,
        comment: "Great",
        created_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

      props =
        visit(:get, "/support/tickets/#{ctx.ticket.reference}", ctx.customer)
        |> page!("Escalated/Customer/Show")

      ticket =
        assert_keys(
          props["ticket"],
          ~w(reference subject description status priority department attachments replies satisfaction_rating created_at)
        )

      assert ticket["department"] == %{"name" => "Billing"}
      assert ticket["satisfaction_rating"] == %{"rating" => 5, "comment" => "Great"}
      assert [reply] = ticket["replies"]
      assert_keys(reply, @reply_keys, "reply")
      assert reply["body"] == "On it"
      assert reply["author"] == %{"name" => "Al Agent"}
      refute Map.has_key?(ticket, "assigned_to")
      refute Map.has_key?(ticket, "metadata")
      refute Jason.encode!(props) =~ "Secret note"
    end

    test "Escalated/Customer/Create sends departments and priorities", ctx do
      props =
        visit(:get, "/support/tickets/new", ctx.customer) |> page!("Escalated/Customer/Create")

      assert_keys(props, ~w(departments priorities))
      assert_keys(hd(props["departments"]), ~w(id name), "department")
    end
  end

  describe "writes the staff pages post" do
    for scope <- ["admin", "agent"] do
      @scope scope

      test "#{scope}: status and priority accept the POST the page sends", ctx do
        user = if @scope == "admin", do: ctx.admin, else: ctx.agent
        base = "/support/#{@scope}/tickets/#{ctx.ticket.reference}"

        conn = visit(:post, base <> "/status", user, %{"status" => "in_progress"})
        assert conn.status in [302, 303]
        conn = visit(:post, base <> "/priority", user, %{"priority" => "urgent"})
        assert conn.status in [302, 303]

        ticket = repo().get!(Ticket, ctx.ticket.id)
        assert ticket.status == "in_progress"
        assert ticket.priority == "urgent"
      end

      test "#{scope}: follow toggles the follower row", ctx do
        user = if @scope == "admin", do: ctx.admin, else: ctx.agent
        path = "/support/#{@scope}/tickets/#{ctx.ticket.reference}/follow"
        followers = fn -> repo().aggregate(TicketFollower, :count) end

        assert visit(:post, path, user, %{}).status in [302, 303]
        assert followers.() == 1
        assert visit(:post, path, user, %{}).status in [302, 303]
        assert followers.() == 0
      end

      test "#{scope}: macro applies the chosen macro", ctx do
        user = if @scope == "admin", do: ctx.admin, else: ctx.agent

        macro =
          repo().insert!(
            Macro.changeset(%Macro{}, %{
              name: "Urgent",
              actions: [%{"type" => "change_priority", "value" => "urgent"}],
              created_by: user.id
            })
          )

        conn =
          visit(:post, "/support/#{@scope}/tickets/#{ctx.ticket.reference}/macro", user, %{
            "macro_id" => macro.id
          })

        assert conn.status in [302, 303]
        assert repo().get!(Ticket, ctx.ticket.id).priority == "urgent"
      end

      test "#{scope}: pin toggles a reply's pin", ctx do
        user = if @scope == "admin", do: ctx.admin, else: ctx.agent
        path = "/support/#{@scope}/tickets/#{ctx.ticket.reference}/replies/#{ctx.note.id}/pin"

        assert visit(:post, path, user, %{}).status in [302, 303]
        assert repo().get!(Reply, ctx.note.id).is_pinned
        assert visit(:post, path, user, %{}).status in [302, 303]
        refute repo().get!(Reply, ctx.note.id).is_pinned
      end

      test "#{scope}: presence answers the other viewers", ctx do
        user = if @scope == "admin", do: ctx.admin, else: ctx.agent
        # Someone else allowed on the same desk.
        other = host_user!(%{name: "Second Viewer", is_admin: @scope == "admin", is_agent: true})
        path = "/support/#{@scope}/tickets/#{ctx.ticket.reference}/presence"

        assert visit(:post, path, other, %{}).status == 200
        conn = visit(:post, path, user, %{})

        assert conn.status == 200
        assert %{"viewers" => viewers} = Jason.decode!(conn.resp_body)
        # Presence is node-wide and outlives the sandbox, so earlier tests'
        # viewers may linger on a reused id; only these two are checked.
        ids = Enum.map(viewers, & &1["id"])
        assert other.id in ids
        refute user.id in ids
      end
    end

    test "a pin on another ticket's reply is refused", ctx do
      {:ok, other} = TicketService.create(%{subject: "Other", description: "x"})
      path = "/support/admin/tickets/#{other.reference}/replies/#{ctx.note.id}/pin"

      assert visit(:post, path, ctx.admin, %{}).status == 404
      refute repo().get!(Reply, ctx.note.id).is_pinned
    end
  end

  describe "writes the customer pages post" do
    test "store takes the flat form the Create page posts", ctx do
      conn =
        visit(:post, "/support/tickets", ctx.customer, %{
          "subject" => "New one",
          "description" => "Help",
          "priority" => "low",
          "department_id" => ctx.department.id,
          "ticket_type" => "question"
        })

      assert conn.status in [302, 303]
      ticket = repo().get_by!(Ticket, subject: "New one")
      assert ticket.requester_id == ctx.customer.id
      assert location(conn) == "/support/tickets/#{ticket.reference}"
    end

    test "close and reopen change the customer's own ticket", ctx do
      path = "/support/tickets/#{ctx.ticket.reference}"

      assert visit(:post, path <> "/close", ctx.customer, %{}).status in [302, 303]
      assert repo().get!(Ticket, ctx.ticket.id).status == "closed"
      assert visit(:post, path <> "/reopen", ctx.customer, %{}).status in [302, 303]
      assert repo().get!(Ticket, ctx.ticket.id).status == "reopened"
    end

    test "close refuses someone else's ticket", ctx do
      stranger = host_user!(%{name: "Stranger"})
      conn = visit(:post, "/support/tickets/#{ctx.ticket.reference}/close", stranger, %{})
      assert conn.status == 403
      assert repo().get!(Ticket, ctx.ticket.id).status != "closed"
    end
  end
end
