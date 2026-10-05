defmodule Escalated.Plugs.GuestSubmissionRateLimit do
  @moduledoc """
  Per-client-IP limits on the unauthenticated guest endpoints that write: ticket
  creation and guest replies. Every accepted request creates rows and sends
  mail, so on top of the shared `:widget_rate_limit` / `:guest_rate_limit`
  budgets each has its own counter, over a 60-second window:

      config :escalated,
        guest_submission_rate_limit: %{
          enabled: true,          # false only when the host throttles upstream
          tickets_per_minute: 5,
          replies_per_minute: 10
        }

  The routes pipe through `GuestTicketRateLimit` or `GuestReplyRateLimit`, which
  run before the controller resolves a guest token, so replies carrying a wrong
  token are counted too. A refused request gets `429` with `Retry-After`.

  The client is the transport's remote IP (see `Escalated.Plugs.PublicRateLimit`).
  Behind a proxy the host must configure trusted proxies (e.g. `Plug.RewriteOn`
  or `remote_ip`) before the router, or every guest shares the proxy's address.
  Counters go to `:rate_limit_backend` (default `Escalated.RateLimiter`, node-local
  ETS), so a cluster can share them by configuring a shared backend.
  """
  alias Escalated.Plugs.PublicRateLimit

  @defaults %{enabled: true, tickets_per_minute: 5, replies_per_minute: 10}
  @window_ms 60_000

  @doc "The limits used for any key the host leaves unset."
  def defaults, do: @defaults

  @doc false
  def call(conn, scope) when scope in [:ticket, :reply] do
    config = PublicRateLimit.config(:guest_submission_rate_limit, @defaults)

    cond do
      config.enabled == false ->
        conn

      PublicRateLimit.valid_config?(%{max_requests: limit(config, scope), window_ms: @window_ms}) ->
        key = Escalated.RateLimiter.client_key(conn.remote_ip)
        PublicRateLimit.enforce(conn, [{bucket(scope), key, limit(config, scope), @window_ms}])

      true ->
        PublicRateLimit.unavailable(conn)
    end
  rescue
    _ -> PublicRateLimit.unavailable(conn)
  end

  defp limit(config, :ticket), do: config.tickets_per_minute
  defp limit(config, :reply), do: config.replies_per_minute

  defp bucket(:ticket), do: :guest_ticket
  defp bucket(:reply), do: :guest_reply
end
