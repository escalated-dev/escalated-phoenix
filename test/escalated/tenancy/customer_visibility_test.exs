defmodule Escalated.Tenancy.CustomerVisibilityTest do
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Controllers.Customer.TicketController
  alias Escalated.HostTestRepo
  alias Escalated.Schemas.{Contact, Reply, Ticket}
  alias Escalated.Serializers.TicketSerializer
  alias Escalated.Tenancy
  alias Escalated.Test.{HostUser, TenantResolver}
  alias Escalated.TestRepo

  setup do
    keys = [:tenancy_enabled, :tenant_resolver, :user_schema, :user_repo, :ui_enabled]
    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, TenantResolver)
    Application.put_env(:escalated, :user_schema, HostUser)
    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :ui_enabled, false)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(HostTestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(HostTestRepo, {:shared, self()})

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.checkin(HostTestRepo)

      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    user = HostTestRepo.insert!(%HostUser{name: "merchant-a", email: "requester@example.test"})
    %{user: user}
  end

  test "customer lists distinguish a contact requester from a host user with the same ID", %{
    user: user
  } do
    # The host users database and package contacts have independent ID sequences.
    TestRepo.insert!(
      Contact.changeset(%Contact{id: user.id, tenant_id: "merchant-a"}, %{
        email: "other-requester@example.test",
        name: "Contact recipient"
      })
    )

    Tenancy.run("merchant-a", fn ->
      own = ticket!(user.id, to_string(HostUser), "Owned correspondence")
      contact = ticket!(user.id, "contact", "Private contact correspondence")
      response = customer_conn(user, "/support/tickets") |> TicketController.index(%{})
      assert response.status == 200
      assert [%{"id" => id}] = Jason.decode!(response.resp_body)["tickets"]["data"]
      assert id == own.id
      refute response.resp_body =~ contact.subject
      refute response.resp_body =~ contact.reference
      contact_fields = TicketSerializer.computed_fields(contact)
      assert contact_fields.requester_name == "Contact recipient"
      assert contact_fields.requester_email == "other-requester@example.test"
      assert TicketSerializer.detail_fields(own).requester_ticket_count == 1
      assert TicketSerializer.detail_fields(contact).requester_ticket_count == 1
      unknown = TicketSerializer.computed_fields(%{own | requester_type: "host-custom-entity"})
      assert is_nil(unknown.requester_name)
      assert is_nil(unknown.requester_email)
    end)
  end

  test "customer pages exclude internal-note author and timestamp from last-reply metadata", %{
    user: user
  } do
    Tenancy.run("merchant-a", fn ->
      ticket = ticket!(user.id, to_string(HostUser), "Owned correspondence")
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      public_time = DateTime.add(now, -60)
      reply!(ticket, %{body: "Public answer", is_internal: false, inserted_at: public_time})

      reply!(ticket, %{
        body: "Private staff discussion",
        is_internal: true,
        author_id: user.id,
        inserted_at: now
      })

      response = customer_conn(user, "/support/tickets") |> TicketController.index(%{})
      assert [row] = Jason.decode!(response.resp_body)["tickets"]["data"]
      assert row["last_reply_at"] == DateTime.to_iso8601(public_time)
      assert is_nil(row["last_reply_author"])

      detail =
        customer_conn(user, "/support/tickets/#{ticket.reference}")
        |> TicketController.show(%{"reference" => ticket.reference})
        |> Map.fetch!(:resp_body)
        |> Jason.decode!()

      assert detail["ticket"]["last_reply_at"] == DateTime.to_iso8601(public_time)
      assert is_nil(detail["ticket"]["last_reply_author"])
      assert [%{"body" => "Public answer"}] = detail["ticket"]["replies"]
      assert TicketSerializer.computed_fields(ticket).last_reply_at == DateTime.to_iso8601(now)
    end)
  end

  test "internal-only threads have no public last-reply metadata", %{user: user} do
    Tenancy.run("merchant-a", fn ->
      ticket = ticket!(user.id, to_string(HostUser), "Awaiting public reply")
      reply!(ticket, %{body: "Internal note", is_internal: true, author_id: user.id})
      fields = TicketSerializer.computed_fields(ticket, public: true)
      assert is_nil(fields.last_reply_at)
      assert is_nil(fields.last_reply_author)
      assert TicketSerializer.computed_fields(ticket).last_reply_author == user.name
    end)
  end

  defp customer_conn(user, path), do: conn(:get, path) |> assign(:current_user, user)

  defp ticket!(id, type, subject),
    do:
      Escalated.repo().insert!(
        Ticket.changeset(%Ticket{}, %{
          subject: subject,
          description: subject,
          requester_id: id,
          requester_type: type
        })
      )

  defp reply!(ticket, attrs) do
    inserted_at = attrs[:inserted_at] || DateTime.utc_now() |> DateTime.truncate(:second)

    %Reply{}
    |> Reply.changeset(Map.put(attrs, :ticket_id, ticket.id))
    |> Ecto.Changeset.put_change(:inserted_at, inserted_at)
    |> Escalated.repo().insert!()
  end
end
