defmodule Escalated.Services.WebhookDispatcher do
  @moduledoc """
  Delivers outbound webhook events to subscribed endpoints.

  Mirrors the Laravel `Escalated\\Laravel\\Services\\WebhookDispatcher`:

    * `dispatch/2` fans an event out to every active webhook subscribed to it.
    * Each delivery POSTs a JSON body `%{"event", "payload", "timestamp"}` with
      an `x-escalated-event` header and, when the webhook has a secret, an
      `x-escalated-signature` header (lower-case hex HMAC-SHA256 of the raw
      body). One `WebhookDelivery` row is written per attempt.
    * Non-2xx responses (and transport errors) retry up to 3 attempts total
      with exponential backoff.
    * `retry_delivery/1` replays a recorded delivery on demand.

  Delivery is fire-and-forget via `Task.start/1` so a slow endpoint never blocks
  the request that triggered the event; the `WebhookDelivery` row is still
  recorded by the spawned task. Set `config :escalated, :webhook_sync, true`
  (as the test suite does) to run delivery inline instead.

  The HTTP client is pluggable via `config :escalated, :webhook_http_client`
  (a `{module, function}` or 3-arity `fun.(url, headers, body)`), defaulting to
  a thin wrapper over Erlang's stdlib `:httpc` — no external HTTP dependency,
  matching `Escalated.Services.Email.Inbound.AttachmentDownloader`.
  """

  require Logger

  alias Escalated.Schemas.{Webhook, WebhookDelivery}
  alias Escalated.Webhooks

  @max_attempts 3
  @timeout_ms 10_000

  @doc """
  Dispatch an event to every active webhook subscribed to it.

  Runs defensively: a failure resolving or delivering to subscribers is logged
  and swallowed so it can never break the caller (e.g. ticket creation).
  """
  def dispatch(event, payload) when is_binary(event) and is_map(payload) do
    repo = Escalated.repo()

    repo
    |> Webhooks.subscribed_to(event)
    |> Enum.each(fn webhook -> deliver_async(webhook, event, payload, 1) end)

    :ok
  rescue
    error ->
      Logger.warning("Escalated webhook dispatch for #{event} failed: #{inspect(error)}")
      :ok
  end

  @doc """
  Send a single delivery (attempt `attempt`), recording a `WebhookDelivery`
  row and retrying on failure. Returns the persisted delivery (or `nil` when
  the delivery row could not be inserted).
  """
  def send(%Webhook{} = webhook, event, payload, attempt \\ 1) do
    body = encode_body(event, payload)
    headers = build_headers(webhook, event, body)

    delivery = insert_delivery(webhook, event, payload, attempt)

    case http_post(webhook.url, headers, body) do
      {:ok, %{status: status, body: response_body}} ->
        delivery = record_response(delivery, status, response_body, attempt)

        if not success?(status) and attempt < @max_attempts do
          retry_later(webhook, event, payload, attempt + 1)
        end

        delivery

      {:error, reason} ->
        message = inspect(reason)
        delivery = record_error(delivery, message, attempt)

        Logger.warning(
          "Escalated webhook delivery failed (webhook #{webhook.id}, event #{event}, " <>
            "attempt #{attempt}): #{message}"
        )

        if attempt < @max_attempts do
          retry_later(webhook, event, payload, attempt + 1)
        end

        delivery
    end
  end

  @doc "Replay a recorded delivery from the start (a fresh attempt chain)."
  def retry_delivery(%WebhookDelivery{} = delivery) do
    repo = Escalated.repo()

    case repo.get(Webhook, delivery.webhook_id) do
      nil -> :ok
      %Webhook{} = webhook -> deliver_async(webhook, delivery.event, delivery.payload || %{}, 1)
    end
  end

  @doc "Maximum number of delivery attempts before giving up."
  def max_attempts, do: @max_attempts

  # ---------- delivery mechanics ----------

  defp deliver_async(webhook, event, payload, attempt) do
    run(fn -> send(webhook, event, payload, attempt) end)
  end

  defp retry_later(webhook, event, payload, attempt) do
    delay = backoff_ms(attempt)

    run(fn ->
      if delay > 0, do: Process.sleep(delay)
      send(webhook, event, payload, attempt)
    end)
  end

  # Inline when synchronous (tests / hosts that opt in), otherwise an unlinked
  # task so a slow endpoint never blocks the triggering request.
  defp run(fun) do
    if sync?() do
      fun.()
    else
      {:ok, _pid} = Task.start(fun)
      :ok
    end
  end

  defp sync?, do: Application.get_env(:escalated, :webhook_sync, false) == true

  # 2^attempt * base seconds -> 120s, 240s with the 30s default base. Backoff is
  # skipped inline in sync mode (see `retry_later/4`, which only sleeps > 0).
  defp backoff_ms(attempt) do
    if sync?() do
      0
    else
      base = Application.get_env(:escalated, :webhook_backoff_base_ms, 30_000)
      round(:math.pow(2, attempt)) * base
    end
  end

  # ---------- request building ----------

  defp encode_body(event, payload) do
    Jason.encode!(%{
      "event" => event,
      "payload" => payload,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp build_headers(%Webhook{secret: secret}, event, body) do
    base = [
      {"content-type", "application/json"},
      {"x-escalated-event", event}
    ]

    if is_binary(secret) and secret != "" do
      [{"x-escalated-signature", sign(body, secret)} | base]
    else
      base
    end
  end

  @doc "Lower-case hex HMAC-SHA256 signature of `body` with `secret`."
  def sign(body, secret) do
    :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
  end

  # ---------- delivery persistence ----------

  defp insert_delivery(webhook, event, payload, attempt) do
    Escalated.repo().insert(
      WebhookDelivery.changeset(%WebhookDelivery{}, %{
        webhook_id: webhook.id,
        event: event,
        payload: payload,
        attempts: attempt
      })
    )
    |> case do
      {:ok, delivery} -> delivery
      {:error, _changeset} -> nil
    end
  end

  defp record_response(nil, _status, _body, _attempt), do: nil

  defp record_response(delivery, status, response_body, attempt) do
    update_delivery(delivery, %{
      response_code: status,
      response_body: truncate(response_body),
      delivered_at: now(),
      attempts: attempt
    })
  end

  defp record_error(nil, _message, _attempt), do: nil

  defp record_error(delivery, message, attempt) do
    update_delivery(delivery, %{
      response_code: 0,
      response_body: truncate(message),
      attempts: attempt
    })
  end

  defp update_delivery(delivery, attrs) do
    case Escalated.repo().update(WebhookDelivery.changeset(delivery, attrs)) do
      {:ok, updated} -> updated
      {:error, _changeset} -> delivery
    end
  end

  defp truncate(nil), do: nil
  defp truncate(body) when is_binary(body), do: String.slice(body, 0, 2000)
  defp truncate(body), do: body |> to_string() |> String.slice(0, 2000)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp success?(status) when is_integer(status), do: status >= 200 and status < 300
  defp success?(_), do: false

  # ---------- HTTP transport ----------

  defp http_post(url, headers, body) do
    case Application.get_env(:escalated, :webhook_http_client) do
      nil -> default_post(url, headers, body)
      fun when is_function(fun, 3) -> fun.(url, headers, body)
      {mod, fun} -> apply(mod, fun, [url, headers, body])
    end
  end

  # Wrap :httpc — stdlib, no external dep. Starts inets/ssl so :httpc is
  # available even if the host didn't pre-start it.
  defp default_post(url, headers, body) do
    _ = :application.ensure_all_started(:inets)
    _ = :application.ensure_all_started(:ssl)

    {content_type, other_headers} = split_content_type(headers)

    charlist_url = String.to_charlist(url)

    charlist_headers =
      Enum.map(other_headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    request = {charlist_url, charlist_headers, String.to_charlist(content_type), body}
    http_opts = [timeout: @timeout_ms, connect_timeout: @timeout_ms]

    case :httpc.request(:post, request, http_opts, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _resp_headers, resp_body}} ->
        {:ok, %{status: status, body: to_string(resp_body)}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  # :httpc wants the content-type as its own argument, not in the header list.
  defp split_content_type(headers) do
    {ct, rest} =
      Enum.split_with(headers, fn {k, _} -> String.downcase(to_string(k)) == "content-type" end)

    content_type =
      case ct do
        [{_, value} | _] -> value
        _ -> "application/json"
      end

    {content_type, rest}
  end
end
