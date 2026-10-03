defmodule Escalated.Plugs.WidgetChatRateLimit do
  @moduledoc """
  Throttles guest chat polling, messages and typing using `:widget_chat_rate_limit`.

  The shared widget polls every three seconds and sends a typing ping at most
  every three seconds, so one open chat outgrows the general widget budget. These
  routes are charged to their own bucket instead:

    * `max_requests` per `window_ms` for each chat capability from one network
      (the capability is hashed; the raw token never reaches the backend), and
    * `max_requests_per_ip` per `window_ms` for all chat capabilities from one
      network, so changing guessed tokens cannot mint fresh budgets.

  Defaults: 90 per capability and 300 per network each minute.
  """
  @behaviour Plug

  alias Escalated.Plugs.PublicRateLimit

  @defaults %{max_requests: 90, max_requests_per_ip: 300, window_ms: 60_000}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    config = PublicRateLimit.config(:widget_chat_rate_limit, @defaults)

    if PublicRateLimit.valid_config?(config) and is_integer(config.max_requests_per_ip) and
         config.max_requests_per_ip > 0 do
      network = Escalated.RateLimiter.client_key(conn.remote_ip)

      PublicRateLimit.enforce(conn, [
        {:widget_chat_network, network, config.max_requests_per_ip, config.window_ms},
        {:widget_chat, {network, capability(conn)}, config.max_requests, config.window_ms}
      ])
    else
      PublicRateLimit.unavailable(conn)
    end
  rescue
    _ -> PublicRateLimit.unavailable(conn)
  end

  defp capability(conn) do
    token =
      conn.path_params["token"] ||
        List.first(Plug.Conn.get_req_header(conn, "x-guest-token")) ||
        List.first(Plug.Conn.get_req_header(conn, "x-guest-access-token")) ||
        bearer(conn) || ""

    :crypto.hash(:sha256, token) |> binary_part(0, 16) |> Base.encode16(case: :lower)
  end

  defp bearer(conn) do
    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end
end
