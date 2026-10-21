defmodule Escalated.NotificationsTest do
  @moduledoc """
  Outbound ticket notification emails, sent through the host's mailer.

  Recipients follow escalated-laravel's notification listeners
  (SendNewTicketNotifications, SendReplyNotifications,
  SendAssignmentNotification, SendStatusChangeNotification,
  SendSlaBreachNotification, SendEscalationNotification). Threading headers
  follow its NotificationThreading. Agent and customer actions go through the
  real router, the way a host mounts them.
  """
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Ecto.Adapters.SQL.Sandbox
  alias Escalated.HostTestRepo
  alias Escalated.Schemas.{Ticket, Workflow}
  alias Escalated.Services.{Email.MessageIdUtil, SlaService, TicketService}
  alias Escalated.Test.{HostUser, Router}

  @domain "support.example.com"
  @secret "notification-test-inbound-secret"

  defmodule Mailer do
    @moduledoc false
    use Swoosh.Mailer, otp_app: :escalated
  end

  @keys [
    :user_repo,
    :user_schema,
    :agent_check,
    :email_domain,
    :email_inbound_secret,
    :from_email,
    :notification_delivery,
    :notification_sync,
    :notification_channels,
    :mailer,
    Mailer
  ]

  setup do
    previous = Map.new(@keys, &{&1, Application.fetch_env(:escalated, &1)})

    :ok = Sandbox.checkout(HostTestRepo)
    Sandbox.mode(HostTestRepo, {:shared, self()})

    test_pid = self()
    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :user_schema, HostUser)
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
    Application.put_env(:escalated, :email_domain, @domain)
    Application.put_env(:escalated, :email_inbound_secret, @secret)
    Application.put_env(:escalated, :from_email, "help@#{@domain}")
    Application.put_env(:escalated, :notification_sync, true)

    Application.put_env(:escalated, :notification_delivery, fn email ->
      send(test_pid, {:mail, email})
      :ok
    end)

    on_exit(fn ->
      Sandbox.checkin(HostTestRepo)

      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    customer = HostTestRepo.insert!(%HostUser{name: "Cara", email: "cara@example.com"})
    agent = HostTestRepo.insert!(%HostUser{name: "Ali", email: "ali@example.com", is_agent: true})

    other =
      HostTestRepo.insert!(%HostUser{name: "Bo", email: "bo@example.com", is_agent: true})

    %{customer: customer, agent: agent, other: other}
  end

  describe "new ticket" do
    test "the requester gets the thread anchor, with a signed Reply-To", %{customer: customer} do
      conn =
        visit(:post, "/support/tickets", user(customer), %{
          "ticket" => %{"subject" => "Printer jammed", "description" => "It beeps"}
        })

      assert conn.status == 302
      ticket = Escalated.repo().get_by!(Ticket, subject: "Printer jammed")

      [mail] = mails()
      assert mail.to == "cara@example.com"
      assert mail.from == {"Support", "help@#{@domain}"}
      assert mail.subject == "[#{ticket.reference}] New Ticket: Printer jammed"
      assert mail.headers["Message-ID"] == "<ticket-#{ticket.id}@#{@domain}>"
      refute Map.has_key?(mail.headers, "In-Reply-To")
      assert mail.reply_to == MessageIdUtil.build_reply_to(ticket.id, @secret, @domain)
      assert mail.text_body =~ "It beeps"
    end

    test "an assigned agent is told too", %{customer: customer, agent: agent} do
      {:ok, _} =
        TicketService.create(%{
          subject: "Login",
          description: "x",
          requester_id: customer.id,
          requester_type: "user",
          assigned_to: agent.id
        })

      assert Enum.sort(Enum.map(mails(), & &1.to)) == ["ali@example.com", "cara@example.com"]
    end

    test "a guest ticket goes to the guest's address" do
      {:ok, _} =
        TicketService.create(%{
          subject: "Hello",
          description: "x",
          guest_name: "Gus",
          guest_email: "gus@example.net",
          requester_type: "guest"
        })

      assert [%{to: "gus@example.net"}] = mails()
    end
  end

  describe "replies" do
    test "an agent's reply goes to the requester, threaded, and not to the agent",
         %{customer: customer, agent: agent} do
      ticket = ticket!(customer, assigned_to: agent.id)

      conn =
        visit(:post, "/support/agent/tickets/#{ticket.reference}/reply", user(agent), %{
          "body" => "Try turning it off"
        })

      assert conn.status == 302
      [mail] = mails()
      [reply] = Escalated.repo().all(Escalated.Schemas.Reply)

      assert mail.to == "cara@example.com"
      assert mail.subject == "Re: [#{ticket.reference}] #{ticket.subject}"
      assert mail.headers["Message-ID"] == "<ticket-#{ticket.id}-reply-#{reply.id}@#{@domain}>"
      assert mail.headers["In-Reply-To"] == "<ticket-#{ticket.id}@#{@domain}>"
      assert mail.headers["References"] == "<ticket-#{ticket.id}@#{@domain}>"
      assert mail.reply_to == MessageIdUtil.build_reply_to(ticket.id, @secret, @domain)
      assert mail.text_body =~ "Try turning it off"
    end

    test "a customer's reply goes to the assignee, not back to the customer",
         %{customer: customer, agent: agent} do
      ticket = ticket!(customer, assigned_to: agent.id)

      conn =
        visit(:post, "/support/tickets/#{ticket.reference}/reply", user(customer), %{
          "body" => "Still broken"
        })

      assert conn.status == 302
      assert [%{to: "ali@example.com"}] = mails()
    end

    test "followers hear about replies they did not write",
         %{customer: customer, agent: agent, other: other} do
      ticket = ticket!(customer, assigned_to: agent.id)
      {:ok, _} = Escalated.Services.Followers.add_follower(ticket.id, other.id)

      visit(:post, "/support/agent/tickets/#{ticket.reference}/reply", user(agent), %{
        "body" => "On it"
      })

      assert Enum.sort(Enum.map(mails(), & &1.to)) == ["bo@example.com", "cara@example.com"]

      visit(:post, "/support/agent/tickets/#{ticket.reference}/reply", user(other), %{
        "body" => "Me too"
      })

      assert Enum.sort(Enum.map(mails(), & &1.to)) == ["ali@example.com", "cara@example.com"]
    end

    test "an internal note emails nobody", %{customer: customer, agent: agent} do
      ticket = ticket!(customer, assigned_to: agent.id)

      visit(:post, "/support/agent/tickets/#{ticket.reference}/note", user(agent), %{
        "body" => "Private"
      })

      assert mails() == []
    end

    test "an agent's reply on a guest ticket goes to the guest", %{agent: agent} do
      {:ok, ticket} =
        TicketService.create(%{
          subject: "Hello",
          description: "x",
          guest_email: "gus@example.net",
          requester_type: "guest"
        })

      _ = mails()

      visit(:post, "/support/agent/tickets/#{ticket.reference}/reply", user(agent), %{
        "body" => "Hi Gus"
      })

      assert [%{to: "gus@example.net"}] = mails()
    end

    test "a workflow's canned reply goes to the requester and the assignee",
         %{customer: customer, agent: agent} do
      %Workflow{}
      |> Workflow.changeset(%{
        name: "Auto-answer",
        trigger_event: "ticket.created",
        conditions: %{"all" => []},
        actions: [%{"type" => "insert_canned_reply", "value" => "We got it"}]
      })
      |> Escalated.repo().insert!()

      {:ok, _} =
        TicketService.create(%{
          subject: "Printer",
          description: "Jammed",
          requester_id: customer.id,
          requester_type: "user",
          assigned_to: agent.id
        })

      replies = Enum.filter(mails(), &String.starts_with?(&1.subject, "Re: "))
      assert Enum.sort(Enum.map(replies, & &1.to)) == ["ali@example.com", "cara@example.com"]
    end

    test "a live chat message emails nobody", %{customer: customer, agent: agent} do
      ticket = ticket!(customer, assigned_to: agent.id)

      session =
        %Escalated.Schemas.ChatSession{}
        |> Escalated.Schemas.ChatSession.changeset(%{ticket_id: ticket.id, status: "active"})
        |> Escalated.repo().insert!()

      {:ok, _} =
        Escalated.Services.ChatSessionService.send_message(session, "hi",
          author_id: agent.id,
          is_agent: true
        )

      assert mails() == []
    end
  end

  describe "assignment, status, SLA and escalation" do
    test "the assignee is told when a ticket is assigned", %{customer: customer, agent: agent} do
      ticket = ticket!(customer)

      conn =
        visit(:post, "/support/agent/tickets/#{ticket.reference}/assign", user(agent), %{
          "agent_id" => agent.id
        })

      assert conn.status == 302
      [mail] = mails()
      assert mail.to == "ali@example.com"
      assert mail.subject == "[#{ticket.reference}] Ticket Assigned to You"
      assert mail.headers["In-Reply-To"] == "<ticket-#{ticket.id}@#{@domain}>"
    end

    test "the requester is told when the status changes, the agent who changed it is not",
         %{customer: customer, agent: agent, other: other} do
      ticket = ticket!(customer, assigned_to: agent.id)
      {:ok, _} = Escalated.Services.Followers.add_follower(ticket.id, other.id)
      {:ok, _} = Escalated.Services.Followers.add_follower(ticket.id, agent.id)

      conn =
        visit(:patch, "/support/agent/tickets/#{ticket.reference}/status", user(agent), %{
          "status" => "resolved"
        })

      assert conn.status in [302, 303]
      mails = mails()
      assert Enum.sort(Enum.map(mails, & &1.to)) == ["bo@example.com", "cara@example.com"]

      for mail <- mails do
        assert mail.subject == "[#{ticket.reference}] Status Updated: Resolved"
        assert mail.headers["References"] == "<ticket-#{ticket.id}@#{@domain}>"
      end
    end

    test "the requester closing their own ticket is not emailed about it",
         %{customer: customer} do
      ticket = ticket!(customer)

      {:ok, _} = TicketService.transition_status(ticket, "closed", actor_id: customer.id)

      assert mails() == []
    end

    test "an SLA breach goes to the assignee", %{customer: customer, agent: agent} do
      ticket!(customer,
        assigned_to: agent.id,
        sla_first_response_due_at:
          DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
      )

      SlaService.check_breaches()

      assert [%{to: "ali@example.com", subject: subject}] = mails()
      assert subject =~ "[SLA Breach]"
      assert subject =~ "First Response SLA Breached"
    end

    test "an escalation goes to the assignee", %{customer: customer, agent: agent} do
      ticket = ticket!(customer, assigned_to: agent.id)

      {:ok, _} = TicketService.transition_status(ticket, "escalated")

      subjects = mails() |> Enum.filter(&(&1.to == "ali@example.com")) |> Enum.map(& &1.subject)
      assert "[Escalated] [#{ticket.reference}] #{ticket.subject}" in subjects
    end
  end

  describe "configuration" do
    test "nothing is sent while no mailer is configured", %{customer: customer} do
      Application.delete_env(:escalated, :notification_delivery)

      ticket!(customer)

      refute_received {:mail, _}
    end

    test "nothing is sent when :email is not a notification channel", %{customer: customer} do
      Application.put_env(:escalated, :notification_channels, [:database])

      ticket!(customer)

      assert mails() == []
    end

    test "a Swoosh mailer receives a Swoosh email", %{customer: customer} do
      Application.delete_env(:escalated, :notification_delivery)
      Application.put_env(:escalated, Mailer, adapter: Swoosh.Adapters.Test)
      Application.put_env(:escalated, :mailer, Mailer)

      ticket = ticket!(customer)

      assert_received {:email, %Swoosh.Email{} = email}
      assert email.to == [{"", "cara@example.com"}]
      assert email.from == {"Support", "help@#{@domain}"}
      assert email.subject == "[#{ticket.reference}] New Ticket: #{ticket.subject}"
      assert email.headers["Message-ID"] == "<ticket-#{ticket.id}@#{@domain}>"
      assert email.reply_to == {"", MessageIdUtil.build_reply_to(ticket.id, @secret, @domain)}
      assert email.html_body =~ ticket.reference
    end

    test "a failing mailer never breaks the ticket operation", %{customer: customer} do
      Application.put_env(:escalated, :notification_delivery, fn _ -> raise "SMTP down" end)

      assert %Ticket{} = ticket!(customer)
    end
  end

  defp ticket!(customer, attrs \\ []) do
    {:ok, ticket} =
      TicketService.create(
        Map.merge(
          %{
            subject: "Printer",
            description: "Jammed",
            requester_id: customer.id,
            requester_type: "user"
          },
          Map.new(attrs)
        )
      )

    # The new-ticket emails are covered above; start each case clean.
    _ = mails()
    ticket
  end

  defp mails(acc \\ []) do
    receive do
      {:mail, mail} -> mails([mail | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp user(%HostUser{} = u), do: Map.from_struct(u)

  defp visit(method, path, user, body) do
    method
    |> conn(path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> init_test_session(%{})
    |> assign(:current_user, user)
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
end
