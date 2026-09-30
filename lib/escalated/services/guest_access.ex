defmodule Escalated.Services.GuestAccess do
  @moduledoc """
  Verified guest capabilities. Configure `guest_access_secret` (32+ bytes) and
  `guest_verification_delivery`, a trusted function `(email, code, purpose)`
  returning `:ok` or `{:ok, _}`. Delivery errors are never logged or exposed.

  Codes last ten minutes and permit five attempts. Delivery, including failed
  sends, consumes two database budgets per hour: `guest_mailbox_ip_limit` (3) per
  mailbox and client network (IPv6 per /64), and `guest_mailbox_limit` (10) per
  mailbox across every network, tenant and node. A refused request spends neither.
  Creation and one-time proof consumption commit in the same package transaction.
  An identical retry of a consumed proof spends no attempt and returns the original
  result with an equivalent capability for the same, still-current grant. The proof
  row keeps only non-secret result data; the capability is re-derived on replay.

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
  # The proof being consumed, so `issue/3` can derive a replayable grant nonce.
  @proof_key {__MODULE__, :proof}

  def email(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  def email(_), do: ""
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  @doc """
  Sends a mailbox code. Pass the caller's transport address as `ip:` so the
  per-network budget applies to it; without one, all such calls share a network.
  """
  def challenge(address, purpose, opts \\ []) do
    address = email(address)
    delivery = Escalated.config(:guest_verification_delivery)

    cond do
      not valid_email?(address) or purpose not in ["ticket", "chat", "lookup"] ->
        {:error, :invalid}

      not configured?() or not is_function(delivery, 3) ->
        {:error, :unavailable}

      true ->
        with :ok <- charge_mailbox(address, Keyword.get(opts, :ip)),
             do: create_challenge(address, purpose, delivery)
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
    # Every presented code is charged before it is compared, so concurrent guesses
    # cannot exceed the budget; a correct retry of a consumed proof is refunded.
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
        # The right code for an already consumed proof is a retry, not a guess.
        repo.update_all(from(c in GuestChallenge, where: c.id == ^id), inc: [attempts: -1])
        replay(row, fingerprint)

      true ->
        case with_proof(row.id, callback) do
          {:ok, result} ->
            repo.update!(
              Ecto.Changeset.change(row,
                used_at: current,
                request_hash: fingerprint,
                result: stored_result(result)
              ),
              log: false
            )

            {:ok, Map.put(result, "_replayed", false)}

          {:error, reason} ->
            repo.rollback(reason)
        end
    end
  end

  defp with_proof(id, callback) do
    previous = Process.put(@proof_key, id)

    try do
      callback.()
    after
      if previous, do: Process.put(@proof_key, previous), else: Process.delete(@proof_key)
    end
  end

  # Only non-secret data is kept for replay: never the bearer capability.
  defp stored_result(%{"data" => data} = result) when is_list(data),
    do: %{result | "data" => Enum.map(data, &stored_result/1)}

  defp stored_result(result) when is_map(result),
    do: Map.drop(result, ["guest_access_token", "_replayed"])

  defp proof_matches?(row, code, address, purpose) do
    row.email == address and row.purpose == purpose and
      secure?(row.code_hash, digest("proof:" <> row.id <> ":" <> code))
  end

  defp replay(row, fingerprint) do
    with true <- row.request_hash == fingerprint and is_map(row.result),
         true <- DateTime.compare(row.expires_at, now()) == :gt,
         {:ok, result} <- reissue(row) do
      {:ok, Map.put(result, "_replayed", true)}
    else
      _ -> {:error, :verification}
    end
  end

  defp reissue(%GuestChallenge{purpose: "lookup", result: %{"data" => data} = result} = row)
       when is_list(data) do
    reissued = Enum.map(data, &reissue_grant(row.id, &1, "ticket"))

    if Enum.all?(reissued, &match?({:ok, _}, &1)),
      do: {:ok, %{result | "data" => Enum.map(reissued, &elem(&1, 1))}},
      else: :error
  end

  defp reissue(%GuestChallenge{purpose: purpose} = row) when purpose in ["ticket", "chat"],
    do: reissue_grant(row.id, row.result, purpose)

  defp reissue(_), do: :error

  # Rebuilds the capability this proof issued. It only resolves while the grant
  # still carries this proof's nonce, so renewal, revocation, expiry or a changed
  # mailbox refuse the replay exactly as they refuse the original capability.
  defp reissue_grant(proof_id, %{"ticket_id" => ticket_id} = entry, purpose)
       when is_integer(ticket_id) do
    with %GuestGrant{} = grant <-
           Escalated.repo().get_by(GuestGrant, ticket_id: ticket_id, purpose: purpose),
         token = seal(grant, derived_nonce(proof_id, ticket_id, purpose)),
         {:ok, _ticket, _grant} <- resolve(token, purpose) do
      {:ok,
       entry
       |> stored_result()
       |> Map.merge(%{
         "guest_access_token" => token,
         "expires_at" => DateTime.to_iso8601(grant.expires_at)
       })}
    else
      _ -> :error
    end
  end

  defp reissue_grant(_, _, _), do: :error

  defp derived_nonce(proof_id, ticket_id, purpose) do
    :crypto.mac(:hmac, :sha256, secret!(), "grant-nonce:#{proof_id}:#{ticket_id}:#{purpose}")
    |> Base.url_encode64(padding: false)
  end

  defp seal(%GuestGrant{} = grant, nonce) do
    expires = DateTime.to_unix(grant.expires_at)

    claims = %{
      version: 1,
      tenant: Tenancy.current_id!(),
      ticket: grant.ticket_id,
      grant: grant.id,
      purpose: grant.purpose,
      email: grant.email_hash,
      nonce: nonce,
      expires: expires
    }

    max_age = max(1, expires - DateTime.to_unix(now()))
    Phoenix.Token.encrypt(secret!(), @salt <> "." <> grant.purpose, claims, max_age: max_age)
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
    row = repo.one(grant_query(repo, ticket.id, purpose)) || %GuestGrant{}

    # Inside a proof, the nonce is derived from it so an identical retry can
    # rebuild this capability without the proof row ever storing it.
    nonce =
      case Process.get(@proof_key) do
        proof when is_binary(proof) -> derived_nonce(proof, ticket.id, purpose)
        _ -> :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
      end

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
      if row.id do
        # A write by primary key, not update/2: its ownership check re-reads the
        # row with a plain snapshot read, which on MySQL can predate a grant
        # a competing request committed (see grant_query/3).
        rotated = Map.drop(changes, [:ticket_id, :purpose]) |> Map.put(:updated_at, now())

        {1, _} =
          repo.update_all(from(g in GuestGrant, where: g.id == ^row.id),
            set: Map.to_list(rotated)
          )

        struct(row, rotated)
      else
        repo.insert!(Ecto.Changeset.change(row, changes), log: false)
      end

    %{
      "ticket_id" => ticket.id,
      "reference" => ticket.reference,
      "subject" => ticket.subject,
      "guest_access_token" => seal(grant, nonce),
      "expires_at" => DateTime.to_iso8601(expiry)
    }
  end

  # The ticket row lock above serializes rotations, but a MySQL REPEATABLE READ
  # snapshot taken earlier in the proof transaction would still miss a grant the
  # competing request just committed, and inserting a second one would violate
  # the unique key. A locking read sees the committed row. SQLite serializes
  # whole write transactions and has no row locks.
  defp grant_query(repo, ticket_id, purpose) do
    query = from(g in GuestGrant, where: g.ticket_id == ^ticket_id and g.purpose == ^purpose)

    if repo.__adapter__() in [Ecto.Adapters.Postgres, Ecto.Adapters.MyXQL],
      do: lock(query, "FOR UPDATE"),
      else: query
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
    header_token(conn) || params["guest_access_token"] || params["guest_token"] ||
      params["token"]
  end

  @doc "The capability sent as `X-Guest-Token`, `X-Guest-Access-Token` or a bearer token."
  def header_token(conn) do
    List.first(Plug.Conn.get_req_header(conn, "x-guest-token")) ||
      List.first(Plug.Conn.get_req_header(conn, "x-guest-access-token")) ||
      bearer(conn)
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

  defp charge_mailbox(address, ip) do
    # Narrow, platform-only raw access. This never reads tickets or host users.
    repo = Escalated.storage_repo()
    current = now()
    expiry = DateTime.add(current, 3600)

    # Keys are keyed hashes: no address or IP is stored. Always charged in this
    # order, so competing transactions lock the rows in the same order.
    budgets = [
      {digest("mailbox:" <> address <> "|network:" <> network(ip)),
       budget_limit(:guest_mailbox_ip_limit, 3)},
      {digest("mailbox:" <> address), budget_limit(:guest_mailbox_limit, 10)}
    ]

    case repo.transaction(fn ->
           for {key, max} <- budgets,
               not spend(repo, key, max, current, expiry),
               do: repo.rollback(:rate_limited)

           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, :rate_limited} -> {:error, :rate_limited}
      _ -> {:error, :unavailable}
    end
  end

  defp spend(repo, key, max, current, expiry) do
    repo.insert_all(
      GuestMailboxBudget,
      [%{mailbox_hash: key, attempts: 0, expires_at: expiry}],
      on_conflict: :nothing
    )

    repo.update_all(
      from(b in GuestMailboxBudget, where: b.mailbox_hash == ^key and b.expires_at <= ^current),
      set: [attempts: 0, expires_at: expiry]
    )

    match?(
      {1, _},
      repo.update_all(
        from(b in GuestMailboxBudget, where: b.mailbox_hash == ^key and b.attempts < ^max),
        inc: [attempts: 1]
      )
    )
  end

  # IPv6 clients are budgeted per /64, like the public route limits.
  defp network(ip) when is_tuple(ip) do
    case Escalated.RateLimiter.client_key(ip) do
      {_, _, _, _, _, _, _, _} = v6 -> "#{:inet.ntoa(v6)}/64"
      v4 -> to_string(:inet.ntoa(v4))
    end
  rescue
    _ -> "unknown"
  end

  defp network(_), do: "unknown"

  defp budget_limit(name, default) do
    case Escalated.config(name, default) do
      value when is_integer(value) and value in 1..1000 -> value
      _ -> default
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
