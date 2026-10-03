defmodule Escalated.Controllers.InboundEmailReplySenderTest do
  @moduledoc """
  End-to-end inbound email through the controller, the real repo and tenancy:
  a mail that threads onto a ticket becomes a reply only when it is signed for
  that ticket and sent by the ticket's requester, and it is posted as that
  requester. Everything else becomes a new ticket. See developer-context
  `domain-model/email-threading.md`.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query
  import Plug.Conn, only: [put_req_header: 3]
  import Plug.Test

  alias Escalated.Controllers.InboundEmailController
  alias Escalated.{HostTestRepo, Tenancy}
  alias Escalated.Schemas.{Contact, Reply, Ticket}
  alias Escalated.Services.Email.MessageIdUtil
  alias Escalated.Services.TicketService
  alias Escalated.Tenancy.Repo
  alias Escalated.Test.{HostUser, TenantResolver}

  @secret "inbound-reply-sender-secret"
  @domain "support.example.com"

  # Hands the controller whatever message the test put in the process
  # dictionary, so each case controls the parsed headers exactly.
  defmodule StubParser do
    def name, do: "stub"
    def parse(_params), do: {:ok, Process.get(:inbound_reply_sender_message)}
  end

  setup do
    keys = [
      :tenancy_enabled,
      :tenant_resolver,
      :user_schema,
      :user_repo,
      :email_inbound_secret,
      :inbound_parsers
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, TenantResolver)
    Application.put_env(:escalated, :user_schema, HostUser)
    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :email_inbound_secret, @secret)
    Application.put_env(:escalated, :inbound_parsers, [StubParser])
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(HostTestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(HostTestRepo, {:shared, self()})

    on_exit(fn ->
      Tenancy.clear()
      Ecto.Adapters.SQL.Sandbox.checkin(HostTestRepo)

      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    requester = HostTestRepo.insert!(%HostUser{name: "a", email: "owner@example.com"})

    agent =
      HostTestRepo.insert!(%HostUser{name: "a", email: "agent@example.com", is_agent: true})

    %{requester: requester, agent: agent}
  end

  defp deliver(tenant, message) do
    Process.put(:inbound_reply_sender_message, message)

    conn =
      :post
      |> conn("/support/webhook/email/inbound", %{"adapter" => "stub"})
      |> put_req_header("x-escalated-inbound-secret", @secret)

    conn = Tenancy.run(tenant, fn -> InboundEmailController.inbound(conn, conn.body_params) end)
    assert conn.status == 200
    Jason.decode!(conn.resp_body)
  end

  defp message(overrides) do
    Map.merge(
      %{
        from_email: "owner@example.com",
        from_name: "Owner",
        to_email: "support@#{@domain}",
        subject: "RE: Question",
        body_text: "Follow-up."
      },
      overrides
    )
  end

  defp signed(ticket), do: MessageIdUtil.build_reply_to(ticket.id, @secret, @domain)

  defp user_ticket(user, status \\ "open") do
    Tenancy.run("a", fn ->
      {:ok, ticket} =
        TicketService.create(%{
          subject: "Printer",
          description: "d",
          requester_id: user.id,
          requester_type: "user"
        })

      with_status(ticket, status)
    end)
  end

  # A verified guest ticket: no requester user, no inline guest email, the
  # address lives only on the Contact.
  defp contact_ticket(tenant, email, status) do
    Tenancy.run(tenant, fn ->
      contact = Repo.insert!(Contact.changeset(%Contact{}, %{email: email, name: "Guest"}))

      {:ok, ticket} =
        TicketService.create(%{subject: "Order", description: "d", contact_id: contact.id})

      with_status(ticket, status)
    end)
  end

  defp with_status(ticket, "open"), do: ticket

  defp with_status(ticket, status) do
    {:ok, ticket} = TicketService.transition_status(ticket, status)
    ticket
  end

  defp replies(tenant, ticket) do
    Tenancy.run(tenant, fn -> Repo.all(from(r in Reply, where: r.ticket_id == ^ticket.id)) end)
  end

  defp reload(tenant, ticket), do: Tenancy.run(tenant, fn -> Repo.get!(Ticket, ticket.id) end)

  test "a stranger quoting a ticket reference in the subject gets a new ticket", %{
    requester: requester
  } do
    ticket = user_ticket(requester)

    body =
      deliver(
        "a",
        message(%{
          from_email: "stranger@example.net",
          subject: "RE: [#{ticket.reference}] Your order",
          in_reply_to: "<ticket-#{ticket.id}@#{@domain}>"
        })
      )

    assert body["outcome"] == "created_new"
    assert body["ticket_id"] != ticket.id
    assert replies("a", ticket) == []
    assert reload("a", %Ticket{id: body["ticket_id"]}).guest_email == "stranger@example.net"
  end

  test "a stranger with a signed address cannot reopen a closed ticket" do
    ticket = contact_ticket("a", "guest@example.com", "closed")

    body =
      deliver("a", message(%{from_email: "stranger@example.net", to_email: signed(ticket)}))

    assert body["outcome"] == "created_new"
    assert replies("a", ticket) == []
    assert reload("a", ticket).status == "closed"
  end

  test "a From header naming an agent is never posted as that agent", %{
    requester: requester,
    agent: agent
  } do
    ticket = user_ticket(requester)

    body =
      deliver("a", message(%{from_email: "agent@example.com", to_email: signed(ticket)}))

    assert body["outcome"] == "created_new"
    assert replies("a", ticket) == []

    assert Tenancy.run("a", fn ->
             Repo.all(from(r in Reply, where: r.author_id == ^agent.id))
           end) == []
  end

  test "the requester's signed reply posts as the requester and reopens", %{
    requester: requester
  } do
    ticket = user_ticket(requester, "resolved")

    body =
      deliver("a", message(%{from_email: "Owner@Example.COM", to_email: signed(ticket)}))

    assert body["outcome"] == "replied_to_existing"
    assert body["ticket_id"] == ticket.id
    assert [%Reply{author_id: author_id, body: "Follow-up."}] = replies("a", ticket)
    assert author_id == requester.id
    assert reload("a", ticket).status == "reopened"
  end

  test "a verified guest's reply matches the email on the contact" do
    ticket = contact_ticket("a", "guest@example.com", "closed")

    body =
      deliver("a", message(%{from_email: "GUEST@example.com", to_email: signed(ticket)}))

    assert body["outcome"] == "replied_to_existing"
    assert [%Reply{author_id: nil}] = replies("a", ticket)
    assert reload("a", ticket).status == "reopened"
  end

  test "the requester's unsigned reply is a new ticket once a secret is set", %{
    requester: requester
  } do
    ticket = user_ticket(requester)

    body =
      deliver(
        "a",
        message(%{
          subject: "RE: [#{ticket.reference}] Question",
          in_reply_to: "<ticket-#{ticket.id}@#{@domain}>",
          references: "<ticket-#{ticket.id}@#{@domain}>"
        })
      )

    assert body["outcome"] == "created_new"
    assert replies("a", ticket) == []
  end

  test "a signed address for another tenant's ticket does not cross tenants" do
    ticket = contact_ticket("b", "guest@example.com", "open")

    body =
      deliver("a", message(%{from_email: "guest@example.com", to_email: signed(ticket)}))

    assert body["outcome"] == "created_new"
    assert body["ticket_id"] != ticket.id
    assert replies("b", ticket) == []
  end
end
