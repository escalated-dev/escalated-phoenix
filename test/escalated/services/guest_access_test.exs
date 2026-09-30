defmodule Escalated.Services.GuestAccessTest do
  use Escalated.DataCase, async: false
  import Ecto.Query

  alias Escalated.Schemas.{
    Attachment,
    ChatSession,
    Contact,
    GuestChallenge,
    GuestGrant,
    GuestMailboxBudget,
    Reply,
    Ticket
  }

  alias Escalated.Services.{ChatSessionService, GuestAccess, TicketService}
  alias Escalated.Test.GuestAccessHelpers, as: Helpers

  defmodule DenyRateLimit do
    def check(:guest, _, _, _), do: {:deny, 1000}
  end

  setup do
    Helpers.configure()
    :ok
  end

  defp attrs,
    do: %{
      subject: "Parcel",
      description: "Please help",
      guest_name: "Recipient",
      guest_email: "recipient@example.test"
    }

  test "proof and creation commit once; identical retries return the same grant" do
    proof = Helpers.proof("  Recipient@Example.Test ")
    assert {:ok, ticket, result} = TicketService.create_guest(proof, attrs())
    token = result["guest_access_token"]
    assert {:ok, same, repeated} = TicketService.create_guest(proof, attrs())
    assert same.id == ticket.id
    assert {:ok, _, grant} = GuestAccess.resolve(token)
    assert {:ok, _, ^grant} = GuestAccess.resolve(repeated["guest_access_token"])
    assert Escalated.repo().aggregate(Ticket, :count) == 1
    assert Escalated.repo().aggregate(Escalated.Schemas.TicketActivity, :count) == 1
    assert {:ok, resolved, _} = GuestAccess.resolve(token)
    assert resolved.id == ticket.id
    assert resolved.guest_token == nil
    refute String.contains?(token, "recipient@example.test")

    assert {:error, :verification} =
             TicketService.create_guest(proof, %{attrs() | subject: "Changed"})
  end

  test "invalid creation rolls back proof consumption and all database work" do
    proof = Helpers.proof()

    assert {:error, %Ecto.Changeset{}} =
             TicketService.create_guest(proof, %{attrs() | subject: nil})

    assert Escalated.repo().aggregate(Ticket, :count) == 0
    assert Escalated.repo().aggregate(Contact, :count) == 0
    challenge = Escalated.repo().get!(GuestChallenge, proof["verification_id"])
    assert challenge.used_at == nil
    assert {:ok, _, _} = TicketService.create_guest(proof, attrs())
  end

  test "five wrong guesses exhaust a challenge even if the next code is correct" do
    proof = Helpers.proof()
    wrong = Map.put(proof, "verification_code", "wrong")

    for _ <- 1..5,
        do: assert({:error, :verification} = TicketService.create_guest(wrong, attrs()))

    assert {:error, :verification} = TicketService.create_guest(proof, attrs())
    assert Escalated.repo().get!(GuestChallenge, proof["verification_id"]).attempts == 5
    assert Escalated.repo().aggregate(Ticket, :count) == 0
  end

  test "expiry and purpose mismatch reject proof before ticket creation" do
    proof = Helpers.proof("recipient@example.test", "chat")
    assert {:error, :verification} = TicketService.create_guest(proof, attrs())

    Escalated.repo().update_all(GuestChallenge,
      set: [expires_at: DateTime.add(GuestAccess.now(), -1)]
    )

    assert {:error, :verification} =
             GuestAccess.consume(proof, "chat", %{}, fn -> flunk("expired proof callback") end)
  end

  test "one mailbox proof cannot authenticate a different guest_email alias" do
    proof =
      Helpers.proof("attacker@example.test") |> Map.put("guest_email", "recipient@example.test")

    assert {:error, :verification} = TicketService.create_guest(proof, attrs())
    assert Escalated.repo().aggregate(Ticket, :count) == 0
  end

  test "existing host-linked contact identity is never renamed or authenticated" do
    contact =
      Escalated.repo().insert!(
        Contact.changeset(%Contact{}, %{
          email: "recipient@example.test",
          name: "Existing account",
          user_id: 123
        })
      )

    assert {:ok, ticket, _} = TicketService.create_guest(Helpers.proof(), attrs())
    assert ticket.requester_id == nil
    assert Escalated.repo().get!(Contact, contact.id).name == "Existing account"
    assert Escalated.repo().get!(Contact, contact.id).user_id == 123
  end

  test "chat proof is bound to the mailbox in the actual chat attributes" do
    proof = Helpers.proof("attacker@example.test", "chat")

    assert {:error, :verification} =
             ChatSessionService.start_guest(proof, %{
               guest_email: "recipient@example.test",
               message: "Help"
             })

    assert Escalated.repo().aggregate(Ticket, :count) == 0
    assert Escalated.repo().aggregate(ChatSession, :count) == 0
  end

  test "mail budget spans purposes, counts failed delivery, and contains only keyed mailbox hashes" do
    Application.put_env(:escalated, :guest_verification_delivery, fn _, _, _ ->
      raise "secret mail credentials"
    end)

    for purpose <- ["ticket", "chat", "lookup"] do
      assert {:error, :unavailable} = GuestAccess.challenge("RECIPIENT@example.test", purpose)
    end

    assert {:error, :rate_limited} = GuestAccess.challenge("recipient@example.test", "ticket")
    assert Escalated.repo().aggregate(GuestChallenge, :count) == 0
    # One budget for the mailbox from this (unknown) network, one across networks.
    budgets = Escalated.storage_repo().all(GuestMailboxBudget)
    assert Enum.map(budgets, & &1.attempts) == [3, 3]

    for budget <- budgets do
      assert byte_size(budget.mailbox_hash) == 64
      refute String.contains?(budget.mailbox_hash, "recipient")
    end
  end

  test "grants reject tampering, the wrong purpose, revocation, and old permanent tokens" do
    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())
    token = result["guest_access_token"]
    assert {:error, :not_found} = GuestAccess.resolve(token <> "changed")
    assert {:error, :not_found} = GuestAccess.resolve(token, "chat")
    Escalated.repo().update!(Ecto.Changeset.change(ticket, guest_token: "old-permanent-token"))
    assert {:error, :not_found} = GuestAccess.resolve("old-permanent-token")
    assert {:ok, :ok} = GuestAccess.revoke(ticket)
    assert {:error, :not_found} = GuestAccess.resolve(token)
  end

  test "email edits and server-side grant expiry revoke existing capabilities" do
    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())
    token = result["guest_access_token"]
    Escalated.repo().update!(Ecto.Changeset.change(ticket, guest_email: "different@example.test"))
    assert {:error, :not_found} = GuestAccess.resolve(token)

    Escalated.repo().update!(
      Ecto.Changeset.change(Escalated.repo().get!(Ticket, ticket.id),
        guest_email: "recipient@example.test"
      )
    )

    Escalated.repo().update_all(GuestGrant,
      set: [expires_at: DateTime.add(GuestAccess.now(), -1)]
    )

    assert {:error, :not_found} = GuestAccess.resolve(token)
  end

  test "host reference resolver runs only after proof and cannot return another mailbox's ticket" do
    {:ok, own} = TicketService.insert(attrs())
    {:ok, other} = TicketService.insert(%{attrs() | guest_email: "other@example.test"})
    parent = self()

    Application.put_env(:escalated, :guest_reference_resolver, fn reference, email, tenant ->
      send(parent, {:lookup, reference, email, tenant})
      [own.id, other.id]
    end)

    assert {:error, :verification} =
             GuestAccess.lookup(%{"reference" => "TRACK1", "email" => "recipient@example.test"})

    refute_received {:lookup, _, _, _}
    proof = Helpers.proof("recipient@example.test", "lookup") |> Map.put("reference", "TRACK1")
    assert {:ok, %{"data" => [match]}} = GuestAccess.lookup(proof)
    assert match["reference"] == own.reference
    assert_received {:lookup, "TRACK1", "recipient@example.test", ""}
    assert {:ok, _, _} = GuestAccess.resolve(match["guest_access_token"])
  end

  test "renewal after fresh mailbox proof invalidates the earlier grant" do
    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())

    proof =
      Helpers.proof("recipient@example.test", "lookup") |> Map.put("reference", ticket.reference)

    assert {:ok, %{"data" => [renewed]}} = GuestAccess.lookup(proof)
    assert {:error, :not_found} = GuestAccess.resolve(result["guest_access_token"])
    assert {:ok, _, _} = GuestAccess.resolve(renewed["guest_access_token"])
  end

  test "chat proof and ticket/session creation are atomic and issue a different-purpose capability" do
    proof = Helpers.proof("recipient@example.test", "chat")
    attrs = %{guest_name: "Recipient", guest_email: "recipient@example.test", message: "Help"}
    assert {:ok, ticket, session, result} = ChatSessionService.start_guest(proof, attrs)
    assert {:ok, _, same, _} = ChatSessionService.start_guest(proof, attrs)
    assert same.id == session.id
    assert Escalated.repo().aggregate(ChatSession, :count) == 1
    assert {:ok, %{id: id}, _} = GuestAccess.resolve(result["guest_access_token"], "chat")
    assert id == ticket.id
    assert {:error, :not_found} = GuestAccess.resolve(result["guest_access_token"])
  end

  test "widget and API reject creation without proof" do
    params = %{
      "subject" => "Parcel",
      "description" => "Help",
      "email" => "recipient@example.test",
      "name" => "Recipient"
    }

    for action <- [
          &Escalated.Controllers.WidgetController.create_ticket/2,
          &Escalated.Controllers.Api.GuestTicketController.create/2,
          &Escalated.Controllers.WidgetChatController.start/2
        ] do
      assert action.(Plug.Test.conn(:post, "/"), params).status == 422
    end

    assert Escalated.repo().aggregate(Ticket, :count) == 0
  end

  test "guest replies ignore submitted internal-note and author identifiers" do
    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())

    conn =
      Escalated.Controllers.Api.GuestTicketController.reply(
        Plug.Test.conn(:post, "/"),
        %{
          "token" => result["guest_access_token"],
          "body" => "Public",
          "is_internal" => true,
          "author_id" => 123
        }
      )

    assert conn.status == 201
    reply = Escalated.repo().one!(from(r in Reply, where: r.ticket_id == ^ticket.id))
    assert reply.is_internal == false
    assert reply.author_id == nil
  end

  test "concurrent identical proof consumption creates one ticket" do
    proof = Helpers.proof()

    results =
      1..2
      |> Task.async_stream(fn _ -> TicketService.create_guest(proof, attrs()) end,
        max_concurrency: 2,
        timeout: 30_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _, _}}, &1))
    assert Escalated.repo().aggregate(Ticket, :count) == 1
  end

  test "tenant switching neither opens another merchant's grant nor resets mailbox budget" do
    previous = Application.fetch_env(:escalated, :tenancy_enabled)
    Application.put_env(:escalated, :tenancy_enabled, true)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :tenancy_enabled, value)
        :error -> Application.delete_env(:escalated, :tenancy_enabled)
      end
    end)

    token =
      Escalated.Tenancy.run("merchant-a", fn ->
        {:ok, _, result} = TicketService.create_guest(Helpers.proof(), attrs())
        result["guest_access_token"]
      end)

    Escalated.Tenancy.run("merchant-b", fn ->
      assert {:error, :not_found} = GuestAccess.resolve(token)
      assert {:ok, _} = GuestAccess.challenge("recipient@example.test", "ticket")
    end)

    Escalated.Tenancy.run("merchant-c", fn ->
      assert {:ok, _} = GuestAccess.challenge("recipient@example.test", "chat")
      assert {:error, :rate_limited} = GuestAccess.challenge("recipient@example.test", "lookup")
    end)
  end

  test "guest attachments require the current grant and exclude internal replies" do
    previous = Application.fetch_env(:escalated, :attachment_download_url)

    Application.put_env(:escalated, :attachment_download_url, fn _attachment, ttl ->
      assert ttl > 0 and ttl <= 300
      {:ok, "https://private.example.test/temporary"}
    end)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :attachment_download_url, value)
        :error -> Application.delete_env(:escalated, :attachment_download_url)
      end
    end)

    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())

    note =
      Escalated.repo().insert!(
        Reply.changeset(%Reply{}, %{ticket_id: ticket.id, body: "Internal", is_internal: true})
      )

    base = %{
      ticket_id: ticket.id,
      storage_backend: "s3",
      storage_key: "private-photo",
      original_filename: "parcel.jpg",
      mime_type: "image/jpeg",
      size: 10
    }

    public =
      Escalated.repo().insert!(
        Escalated.Schemas.Attachment.changeset(%Escalated.Schemas.Attachment{}, base)
      )

    internal =
      Escalated.repo().insert!(
        Escalated.Schemas.Attachment.changeset(
          %Escalated.Schemas.Attachment{},
          Map.put(base, :reply_id, note.id)
        )
      )

    download = fn id, token ->
      conn =
        Plug.Test.conn(:get, "/support/attachments/#{id}/download")
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_req_header("x-guest-token", token)

      Escalated.Test.Router.call(conn, Escalated.Test.Router.init([]))
    end

    assert download.(public.id, result["guest_access_token"]).status == 302
    assert download.(internal.id, result["guest_access_token"]).status == 404
    GuestAccess.revoke(ticket)
    assert download.(public.id, result["guest_access_token"]).status == 401
  end

  test "guest CSAT rejects permanent tokens and accepts a verified resolved ticket once" do
    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())

    Escalated.repo().update!(
      Ecto.Changeset.change(ticket, status: "resolved", guest_token: "legacy")
    )

    action = &Escalated.Controllers.SatisfactionRatingController.store_guest/2

    assert action.(Plug.Test.conn(:post, "/"), %{"token" => "legacy", "rating" => 5}).status ==
             404

    params = %{"token" => result["guest_access_token"], "rating" => 5}
    assert action.(Plug.Test.conn(:post, "/"), params).status == 201
    assert action.(Plug.Test.conn(:post, "/"), params).status == 422
  end

  test "public read responses exclude guest email and internal notes" do
    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())

    Escalated.repo().insert!(
      Reply.changeset(%Reply{}, %{ticket_id: ticket.id, body: "Secret note", is_internal: true})
    )

    conn =
      Escalated.Controllers.WidgetController.show_ticket(
        Plug.Test.conn(:get, "/"),
        %{"reference" => ticket.reference, "guest_access_token" => result["guest_access_token"]}
      )

    assert conn.status == 200
    refute String.contains?(conn.resp_body, "recipient@example.test")
    refute String.contains?(conn.resp_body, "Secret note")
  end

  test "public correspondence supplies scoped attachment-only links that revoke with the grant" do
    {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())

    reply =
      Escalated.repo().insert!(
        Reply.changeset(%Reply{}, %{
          ticket_id: ticket.id,
          body: "Public update",
          is_internal: false
        })
      )

    note =
      Escalated.repo().insert!(
        Reply.changeset(%Reply{}, %{
          ticket_id: ticket.id,
          body: "Private update",
          is_internal: true
        })
      )

    for {reply_id, name} <- [
          {nil, "parcel.jpg"},
          {reply.id, "receipt.pdf"},
          {note.id, "internal.txt"}
        ] do
      Escalated.repo().insert!(
        Attachment.changeset(%Attachment{}, %{
          ticket_id: ticket.id,
          reply_id: reply_id,
          original_filename: name,
          storage_backend: "s3",
          storage_key: "private-bucket-secret/" <> name,
          size: 10
        })
      )
    end

    token = result["guest_access_token"]

    api =
      Escalated.Controllers.Api.GuestTicketController.show(Plug.Test.conn(:get, "/"), %{
        "token" => token
      })

    payload = Jason.decode!(api.resp_body)["data"]
    assert payload["description"] == "Please help"
    assert [%{"filename" => "parcel.jpg", "url" => url}] = payload["attachments"]

    assert [%{"body" => "Public update", "attachments" => [%{"filename" => "receipt.pdf"}]}] =
             payload["replies"]

    refute String.contains?(api.resp_body, "Private update")
    refute String.contains?(api.resp_body, "internal.txt")
    refute String.contains?(api.resp_body, "private-bucket-secret")
    refute String.contains?(api.resp_body, "recipient@example.test")

    uri = URI.parse(url)
    capability = URI.decode_query(uri.query)["download_token"]
    [_, id] = Regex.run(~r{/attachments/(\d+)/download}, uri.path)
    assert {:ok, _, grant} = GuestAccess.resolve_attachment(capability, id)
    assert DateTime.diff(grant.expires_at, GuestAccess.now()) <= 300
    assert {:error, :not_found} = GuestAccess.resolve(capability)
    assert {:error, :not_found} = GuestAccess.resolve_attachment(capability, "999999")
    assert {:error, :not_found} = GuestAccess.resolve_attachment(capability <> "changed", id)

    conn = Plug.Test.conn(:get, url) |> Plug.Test.init_test_session(%{})
    # The capability alone authenticates, reaching private-storage configuration rather than 401.
    assert Escalated.Test.Router.call(conn, Escalated.Test.Router.init([])).status == 503
    GuestAccess.revoke(ticket)
    assert {:error, :not_found} = GuestAccess.resolve_attachment(capability, id)
    conn = Plug.Test.conn(:get, url) |> Plug.Test.init_test_session(%{})
    assert Escalated.Test.Router.call(conn, Escalated.Test.Router.init([])).status == 401
  end

  test "bounded cleanup deletes expired state without resetting active mailbox limits" do
    {:ok, _, _} = TicketService.create_guest(Helpers.proof(), attrs())
    Helpers.proof("other@example.test")
    current = GuestAccess.now()
    Escalated.repo().update_all(GuestChallenge, set: [expires_at: current])
    Escalated.repo().update_all(GuestGrant, set: [expires_at: current])
    assert GuestAccess.purge_expired(1) == %{challenges: 1, grants: 1}
    assert Escalated.repo().aggregate(GuestChallenge, :count) == 1
    assert GuestAccess.purge_expired() == %{challenges: 1, grants: 0}
    assert GuestAccess.purge_expired_mailboxes() == 0
    # Per mailbox: one network budget and one budget across networks.
    assert Escalated.storage_repo().aggregate(GuestMailboxBudget, :count, :mailbox_hash) == 4
    Escalated.storage_repo().update_all(GuestMailboxBudget, set: [expires_at: current])
    assert GuestAccess.purge_expired_mailboxes(1) == 1
    assert GuestAccess.purge_expired_mailboxes() == 3
  end

  test "cleanup task selects a tenant and preserves other tenant state and active proofs" do
    previous = Application.fetch_env(:escalated, :tenancy_enabled)
    Application.put_env(:escalated, :tenancy_enabled, true)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :tenancy_enabled, value)
        :error -> Application.delete_env(:escalated, :tenancy_enabled)
      end
    end)

    for tenant <- ["merchant-a", "merchant-b"] do
      Escalated.Tenancy.run(tenant, fn ->
        {:ok, _, _} =
          TicketService.create_guest(Helpers.proof(tenant <> "@example.test"), %{
            attrs()
            | guest_email: tenant <> "@example.test"
          })

        Escalated.repo().update_all(GuestChallenge, set: [expires_at: GuestAccess.now()])
        Escalated.repo().update_all(GuestGrant, set: [expires_at: GuestAccess.now()])
        Helpers.proof("active-" <> tenant <> "@example.test")
      end)
    end

    Mix.Tasks.Escalated.PurgeGuestAccess.run(["--tenant", "merchant-a"])

    Escalated.Tenancy.run("merchant-a", fn ->
      assert Escalated.repo().aggregate(GuestChallenge, :count) == 1
      assert Escalated.repo().aggregate(GuestGrant, :count) == 0
    end)

    Escalated.Tenancy.run("merchant-b", fn ->
      assert Escalated.repo().aggregate(GuestChallenge, :count) == 2
      assert Escalated.repo().aggregate(GuestGrant, :count) == 1
    end)

    assert Escalated.storage_repo().aggregate(GuestMailboxBudget, :count, :mailbox_hash) == 8
  end

  test "anonymous attachment attempts share the guest budget while host authentication is exempt" do
    previous = Application.fetch_env(:escalated, :rate_limit_backend)
    Application.put_env(:escalated, :rate_limit_backend, DenyRateLimit)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :rate_limit_backend, value)
        :error -> Application.delete_env(:escalated, :rate_limit_backend)
      end
    end)

    conn =
      Plug.Test.conn(:get, "/support/attachments/1/download?download_token=invalid")
      |> Plug.Test.init_test_session(%{})

    assert Escalated.Test.Router.call(conn, Escalated.Test.Router.init([])).status == 429

    conn =
      Plug.Test.conn(:get, "/support/attachments/1/download")
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.assign(:current_user, %{id: 123, is_agent: true})

    assert Escalated.Test.Router.call(conn, Escalated.Test.Router.init([])).status == 404
  end
end
