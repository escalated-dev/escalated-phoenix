defmodule Escalated.Controllers.GuestPagesTest do
  @moduledoc """
  The guest portal pages, `Escalated/Guest/Create` and `Escalated/Guest/Show`,
  on the verified guest access this package already has (email codes and
  expiring hashed grants), against the props escalated-laravel's
  `Guest\\TicketController` sends and the routes the pages post to.
  """
  use Escalated.PageCase

  require Ecto.Query

  alias Escalated.Schemas.{Department, Reply, SatisfactionRating, Ticket}
  alias Escalated.Services.{GuestAccess, TicketService}
  alias Escalated.Test.GuestAccessHelpers, as: Helpers

  defp repo, do: Escalated.repo()

  # The guest limits are node-wide counters keyed on the client address, which
  # every test request shares. These tests are about the pages, so they count
  # against a limiter of their own and leave the shared budget to the tests of
  # the limits themselves.
  setup do
    server = start_supervised!({Escalated.RateLimiter, name: nil})
    Application.put_env(:escalated, :guest_pages_rate_limit_server, server)
    Application.put_env(:escalated, :rate_limit_backend, __MODULE__.Limiter)

    on_exit(fn ->
      Application.delete_env(:escalated, :rate_limit_backend)
      Application.delete_env(:escalated, :guest_pages_rate_limit_server)
    end)

    :ok
  end

  defmodule Limiter do
    @moduledoc false
    def check(bucket, key, max_requests, window_ms) do
      server = Application.fetch_env!(:escalated, :guest_pages_rate_limit_server)
      Escalated.RateLimiter.check(bucket, key, max_requests, window_ms, server)
    end
  end

  setup do
    Helpers.configure()
    department = repo().insert!(Department.changeset(%Department{}, %{name: "Billing"}))
    %{department: department}
  end

  defp guest_ticket! do
    proof = Helpers.proof("guest@example.test")

    {:ok, ticket, result} =
      TicketService.create_guest(proof, %{
        subject: "Where is my parcel",
        description: "It is late",
        guest_name: "Gus",
        guest_email: "guest@example.test",
        priority: "medium"
      })

    {ticket, result["guest_access_token"]}
  end

  test "Create sends departments, priorities and the verification endpoints", ctx do
    props = visit(:get, "/support/guest/create", nil) |> page!("Escalated/Guest/Create")

    assert_keys(props, ~w(departments priorities verification_url lookup_url))
    assert [%{"id" => id, "name" => "Billing"}] = props["departments"]
    assert id == ctx.department.id
    assert props["verification_url"] == "/support/guest/verification"
    assert props["lookup_url"] == "/support/guest/lookup"
  end

  test "store creates the ticket from a verified form and opens its private page", ctx do
    proof = Helpers.proof("new@example.test")

    conn =
      visit(:post, "/support/guest", nil, %{
        "guest_name" => "Nia",
        "guest_email" => "new@example.test",
        "subject" => "Help",
        "description" => "Please",
        "priority" => "high",
        "department_id" => ctx.department.id,
        "verification_id" => proof["verification_id"],
        "verification_code" => proof["verification_code"]
      })

    assert conn.status in [302, 303]
    ticket = repo().get_by!(Ticket, subject: "Help")
    assert ticket.guest_email == "new@example.test"
    assert ticket.department_id == ctx.department.id
    "/support/guest/" <> token = location(conn)
    assert {:ok, %Ticket{id: id}, _} = GuestAccess.resolve(token)
    assert id == ticket.id
  end

  test "store without a valid code goes back with a verification error" do
    conn =
      visit(:post, "/support/guest", nil, %{
        "guest_name" => "Nia",
        "guest_email" => "new@example.test",
        "subject" => "Help",
        "description" => "Please",
        "verification_id" => Ecto.UUID.generate(),
        "verification_code" => "000000"
      })

    assert conn.status in [302, 303]
    assert get_session(conn, "inertia_errors")[:verification_code]
    assert repo().get_by(Ticket, subject: "Help") == nil
  end

  test "Show sends the requester-safe ticket and the token" do
    {ticket, token} = guest_ticket!()
    TicketService.reply(ticket, %{body: "We are looking", is_internal: false})
    TicketService.reply(ticket, %{body: "Internal only", is_internal: true})

    props = visit(:get, "/support/guest/#{token}", nil) |> page!("Escalated/Guest/Show")

    assert props["token"] == token

    t =
      assert_keys(
        props["ticket"],
        ~w(reference subject description status priority department attachments replies satisfaction_rating guest_access_expires_at created_at)
      )

    assert [reply] = t["replies"]
    assert_keys(reply, ~w(id body is_internal_note author attachments created_at), "reply")
    refute Jason.encode!(props) =~ "Internal only"
    refute Map.has_key?(t, "guest_token")
  end

  test "Show refuses a bad token" do
    assert visit(:get, "/support/guest/not-a-token", nil).status == 404
  end

  test "reply posts as the guest and goes back to the page" do
    {ticket, token} = guest_ticket!()

    conn = visit(:post, "/support/guest/#{token}/reply", nil, %{"body" => "Any news?"})
    assert conn.status in [302, 303]
    assert location(conn) == "/support/guest/#{token}"

    assert [%Reply{body: "Any news?", author_id: nil, is_internal: false}] =
             repo().all(Ecto.Query.from(r in Reply, where: r.ticket_id == ^ticket.id))
  end

  test "a closed ticket takes no reply" do
    {ticket, token} = guest_ticket!()
    {:ok, _} = TicketService.transition_status(ticket, "closed")

    conn = visit(:post, "/support/guest/#{token}/reply", nil, %{"body" => "Hello?"})
    assert conn.status in [302, 303]

    assert repo().aggregate(Ecto.Query.from(r in Reply, where: r.ticket_id == ^ticket.id), :count) ==
             0
  end

  test "rate answers on the page's route and goes back for an Inertia visit" do
    {ticket, token} = guest_ticket!()
    {:ok, _} = TicketService.transition_status(ticket, "resolved")

    conn =
      visit(:post, "/support/guest/#{token}/rate", nil, %{"rating" => 5, "comment" => "Great"})

    assert conn.status in [302, 303]
    assert repo().get_by!(SatisfactionRating, ticket_id: ticket.id).rating == 5
  end
end
