defmodule Escalated.Services.GuestAccess do
  @moduledoc """
  Verified guest capabilities. Configure `guest_access_secret` (32+ bytes) and
  `guest_verification_delivery`, a trusted function `(email, code, purpose)`
  returning `:ok` or `{:ok, _}`. Delivery errors are never logged or exposed.

  Codes last ten minutes and permit five attempts. Delivery consumes a global
  database budget of three attempts per mailbox/hour, including failed sends.
  Creation and one-time proof consumption commit in the same package transaction.
  Identical retries return the original still-valid result without repeating work.

  `guest_reference_resolver` may resolve `(reference, verified_email, tenant_id)`
  to ticket IDs; results are reloaded in the tenant and checked against the
  verified mailbox. No host user account is authenticated or modified.
  """
  import Ecto.Query

  alias Escalated.Schemas.{
    Attachment,
    ChatSession,
    GuestChallenge,
    GuestGrant,
    GuestMailboxBudget,
    Ticket
  }

  alias Escalated.Tenancy
  @salt "escalated.guest.grant.v1"

  def email(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  def email(_), do: ""
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  def challenge(address, purpose) do
    address = email(address)
    delivery = Escalated.config(:guest_verification_delivery)

    cond do
      not valid_email?(address) or purpose not in ["ticket", "chat", "lookup"] ->
        {:error, :invalid}

      not configured?() or not is_function(delivery, 3) ->
        {:error, :unavailable}

      true ->
        with :ok <- charge_mailbox(address), do: create_challenge(address, purpose, delivery)
    end
  end

  defp create_challenge(address, purpose, delivery) do
    id = Ecto.UUID.generate()
    code = :crypto.strong_rand_bytes(8) |> :binary.decode_unsigned() |> rem(100_000_000)
    code = code |> Integer.to_string() |> String.pad_leading(8, "0")

    changes = %{
      id: id,
      email: address,
      purpose: purpose,
      code_hash: digest("proof:" <> id <> ":" <> code),
      expires_at: DateTime.add(now(), 600)
    }

    case Escalated.repo().insert(Ecto.Changeset.change(%GuestChallenge{}, changes), log: false) do
      {:ok, row} ->
        if deliver(delivery, address, code, purpose) do
          {:ok, id}
        else
          Escalated.repo().delete(row, log: false)
          {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  end

  def consume(params, purpose, identity, callback) when is_function(callback, 0) do
    address = email(params["email"] || params["guest_email"])
    id = params["verification_id"]
    code = params["verification_code"]

    if configured?() and valid_email?(address) and match?({:ok, _}, Ecto.UUID.cast(id)) and
         is_binary(code) and byte_size(code) <= 16 do
      fingerprint = digest("request:" <> :erlang.term_to_binary({purpose, address, identity}))

      case Escalated.repo().transaction(fn ->
             consume_locked(id, code, address, purpose, fingerprint, callback)
           end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :verification}
    end
  end

  defp consume_locked(id, code, address, purpose, fingerprint, callback) do
    repo = Escalated.repo()
    current = now()
    # The conditional UPDATE holds the database row lock until callback commit.
    # This works on SQLite as well as PostgreSQL/MySQL without SELECT FOR UPDATE.
    {count, _} =
      repo.update_all(
        from(c in GuestChallenge,
          where: c.id == ^id and c.expires_at > ^current and c.attempts < 5
        ),
        inc: [attempts: 1]
      )

    row = repo.get(GuestChallenge, id)

    cond do
      is_nil(row) ->
        {:error, :verification}

      count != 1 ->
        {:error, :verification}

      not proof_matches?(row, code, address, purpose) ->
        {:error, :verification}

      not is_nil(row.used_at) ->
        replay(row, fingerprint)

      true ->
        case callback.() do
          {:ok, result} ->
            repo.update!(
              Ecto.Changeset.change(row,
                used_at: current,
                request_hash: fingerprint,
                result: result
              ),
              log: false
            )

            {:ok, Map.put(result, "_replayed", false)}

          {:error, reason} ->
            repo.rollback(reason)
        end
    end
  end

  defp proof_matches?(row, code, address, purpose) do
    row.email == address and row.purpose == purpose and
      secure?(row.code_hash, digest("proof:" <> row.id <> ":" <> code))
  end

  defp replay(row, fingerprint) do
    grants = if row.purpose == "lookup", do: row.result["data"] || [], else: [row.result]
    purpose = if row.purpose == "lookup", do: "ticket", else: row.purpose
    active = Enum.all?(grants, &match?({:ok, _, _}, resolve(&1["guest_access_token"], purpose)))

    if row.request_hash == fingerprint and DateTime.compare(row.expires_at, now()) == :gt and
         active do
      {:ok, Map.put(row.result, "_replayed", true)}
    else
      {:error, :verification}
    end
  end

  @doc "Trusted entry point: call only inside a consumed mailbox-proof transaction."
  def issue(%Ticket{} = ticket, purpose, address) when purpose in ["ticket", "chat"] do
    Tenancy.assert_record!(ticket)
    address = email(address)

    if address == "" or address != email(ticket.guest_email) or not is_nil(ticket.requester_id),
      do: Escalated.repo().rollback(:verification)

    repo = Escalated.repo()
    # Serialize grant rotations (including the first grant) using the owning row.
    repo.update_all(from(t in Ticket, where: t.id == ^ticket.id), set: [guest_token: nil])
    row = repo.get_by(GuestGrant, ticket_id: ticket.id, purpose: purpose) || %GuestGrant{}
    nonce = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    ttl = Escalated.config(:guest_access_ttl_minutes, 1440)
    ttl = if is_integer(ttl), do: max(5, min(10_080, ttl)), else: 1440
    expiry = DateTime.add(now(), ttl * 60)

    changes = %{
      ticket_id: ticket.id,
      purpose: purpose,
      email_hash: digest("email:" <> address),
      nonce_hash: digest("nonce:" <> nonce),
      expires_at: expiry,
      revoked_at: nil
    }

    grant =
      if row.id,
        do: repo.update!(Ecto.Changeset.change(row, changes), log: false),
        else: repo.insert!(Ecto.Changeset.change(row, changes), log: false)

    claims = %{
      version: 1,
      tenant: Tenancy.current_id!(),
      ticket: ticket.id,
      grant: grant.id,
      purpose: purpose,
      email: grant.email_hash,
      nonce: nonce,
      expires: DateTime.to_unix(expiry)
    }

    token = Phoenix.Token.encrypt(secret!(), @salt <> "." <> purpose, claims, max_age: ttl * 60)

    %{
      "ticket_id" => ticket.id,
      "reference" => ticket.reference,
      "subject" => ticket.subject,
      "guest_access_token" => token,
      "expires_at" => DateTime.to_iso8601(expiry)
    }
  end

  def resolve(token, purpose \\ "ticket") do
    with true <- configured?() and purpose in ["ticket", "chat"] and is_binary(token),
         true <- byte_size(token) in 1..4096,
         {:ok,
          %{
            version: 1,
            tenant: tenant,
            ticket: id,
            grant: grant_id,
            purpose: ^purpose,
            email: mail_hash,
            nonce: nonce,
            expires: expiry
          }} <-
           Phoenix.Token.decrypt(secret!(), @salt <> "." <> purpose, token, max_age: 604_800),
         true <-
           tenant == Tenancy.current_id!() and is_integer(expiry) and
             expiry > DateTime.to_unix(now()),
         %GuestGrant{} = grant <- Escalated.repo().get(GuestGrant, grant_id),
         %Ticket{} = ticket <- Escalated.repo().get(Ticket, id),
         true <- grant.ticket_id == id and grant.purpose == purpose and is_nil(grant.revoked_at),
         true <- DateTime.to_unix(grant.expires_at) == expiry and is_nil(ticket.requester_id),
         true <-
           secure?(grant.nonce_hash, digest("nonce:" <> nonce)) and
             secure?(grant.email_hash, mail_hash) and
             secure?(grant.email_hash, digest("email:" <> email(ticket.guest_email))) do
      {:ok, ticket, grant}
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  def revoke(%Ticket{} = ticket) do
    Tenancy.assert_record!(ticket)

    Escalated.repo().transaction(fn ->
      Escalated.repo().update_all(from(t in Ticket, where: t.id == ^ticket.id),
        set: [guest_token: nil]
      )

      Escalated.repo().update_all(from(g in GuestGrant, where: g.ticket_id == ^ticket.id),
        set: [revoked_at: now()]
      )

      :ok
    end)
  end

  @doc "Deletes one bounded batch of expired guest proofs and grants in the current tenant."
  def purge_expired(limit \\ 1000) when is_integer(limit) and limit in 1..1000 do
    current = now()
    repo = Escalated.repo()

    %{
      challenges: delete_expired(repo, GuestChallenge, :id, current, limit),
      grants: delete_expired(repo, GuestGrant, :id, current, limit)
    }
  end

  @doc "Deletes only expired platform mailbox budgets; active budgets are never reset."
  def purge_expired_mailboxes(limit \\ 1000) when is_integer(limit) and limit in 1..1000 do
    delete_expired(Escalated.storage_repo(), GuestMailboxBudget, :mailbox_hash, now(), limit)
  end

  defp delete_expired(repo, schema, key, current, limit) do
    ids =
      repo.all(
        from(row in schema,
          where: row.expires_at <= ^current,
          order_by: [asc: row.expires_at, asc: field(row, ^key)],
          select: field(row, ^key),
          limit: ^limit
        )
      )

    # Recheck expiry during deletion: a concurrent renewal must retain its grant/budget.
    {count, _} =
      repo.delete_all(
        from(row in schema,
          where: field(row, ^key) in ^ids and row.expires_at <= ^current
        )
      )

    count
  end

  @doc "Builds a five-minute, attachment-only capability bound to the current guest grant."
  def attachment_url(%Attachment{} = attachment, token, %GuestGrant{} = grant) do
    Tenancy.assert_record!(attachment)
    Tenancy.assert_record!(grant)
    expiry = min(DateTime.to_unix(grant.expires_at), DateTime.to_unix(now()) + 300)

    capability =
      Phoenix.Token.encrypt(
        secret!(),
        @salt <> ".attachment",
        %{
          attachment: attachment.id,
          access: token,
          purpose: grant.purpose,
          expires: expiry
        },
        max_age: 300
      )

    Attachment.url(attachment) <> "?" <> URI.encode_query(%{"download_token" => capability})
  end

  def resolve_attachment(capability, attachment_id) do
    with true <- configured?() and is_binary(capability) and byte_size(capability) <= 8192,
         {:ok, %{attachment: id, access: token, purpose: purpose, expires: expiry}} <-
           Phoenix.Token.decrypt(secret!(), @salt <> ".attachment", capability, max_age: 300),
         true <- to_string(id) == attachment_id and expiry > DateTime.to_unix(now()),
         {:ok, ticket, grant} <- resolve(token, purpose) do
      {:ok, ticket, %{grant | expires_at: DateTime.from_unix!(expiry)}}
    else
      _ -> {:error, :not_found}
    end
  rescue
    _ -> {:error, :not_found}
  end

  def lookup(params) do
    reference = params["reference"]

    if is_binary(reference) and byte_size(reference) in 1..255 do
      address = email(params["email"])

      consume(params, "lookup", reference, fn ->
        resolver = Escalated.config(:guest_reference_resolver)

        ids =
          if is_function(resolver, 3),
            do: resolver.(reference, address, Tenancy.current_id!()),
            else: []

        ids = if is_list(ids), do: Enum.filter(ids, &is_integer/1) |> Enum.take(20), else: []

        tickets =
          Escalated.repo().all(
            from(t in Ticket,
              where: t.reference == ^reference or t.id in ^ids,
              order_by: [desc: t.id],
              limit: 20
            )
          )

        results =
          tickets
          |> Enum.filter(&(email(&1.guest_email) == address and is_nil(&1.requester_id)))
          |> Enum.map(&issue(&1, "ticket", address))

        {:ok, %{"data" => results}}
      end)
    else
      {:error, :invalid}
    end
  end

  def token(conn, params \\ %{}) do
    List.first(Plug.Conn.get_req_header(conn, "x-guest-token")) ||
      List.first(Plug.Conn.get_req_header(conn, "x-guest-access-token")) ||
      bearer(conn) || params["guest_access_token"] || params["guest_token"] || params["token"]
  end

  defp bearer(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end

  def resolve_session(reference, token) do
    with {:ok, ticket, grant} <- resolve(token, "chat"),
         true <- ticket.reference == reference or to_string(ticket.id) == reference,
         %ChatSession{} = session <- Escalated.repo().get_by(ChatSession, ticket_id: ticket.id) do
      {:ok, ticket, session, grant}
    else
      _ -> {:error, :not_found}
    end
  end

  defp charge_mailbox(address) do
    # Narrow, platform-only raw access. This never reads tickets or host users.
    repo = Escalated.storage_repo()
    key = digest("mailbox:" <> address)
    current = now()
    expiry = DateTime.add(current, 3600)

    case repo.transaction(fn ->
           repo.insert_all(
             GuestMailboxBudget,
             [%{mailbox_hash: key, attempts: 0, expires_at: expiry}],
             on_conflict: :nothing
           )

           repo.update_all(
             from(b in GuestMailboxBudget,
               where: b.mailbox_hash == ^key and b.expires_at <= ^current
             ),
             set: [attempts: 0, expires_at: expiry]
           )

           case repo.update_all(
                  from(b in GuestMailboxBudget, where: b.mailbox_hash == ^key and b.attempts < 3),
                  inc: [attempts: 1]
                ) do
             {1, _} -> :ok
             _ -> {:error, :rate_limited}
           end
         end) do
      {:ok, result} -> result
      _ -> {:error, :unavailable}
    end
  end

  defp deliver(callback, address, code, purpose) do
    case callback.(address, code, purpose) do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp valid_email?(address),
    do: byte_size(address) in 3..255 and Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/u, address)

  defp configured?,
    do:
      is_binary(Escalated.config(:guest_access_secret)) and
        byte_size(Escalated.config(:guest_access_secret)) >= 32

  defp secret!, do: Escalated.config(:guest_access_secret)

  defp digest(value),
    do: :crypto.mac(:hmac, :sha256, secret!(), value) |> Base.encode16(case: :lower)

  defp secure?(left, right) when is_binary(left) and is_binary(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure?(_, _), do: false
end
