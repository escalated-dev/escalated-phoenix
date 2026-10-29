defmodule Escalated.Plugs.TwoFactorRateLimit do
  @moduledoc """
  Throttles the two-factor challenge's verify route: 5 attempts a minute per
  signed-in user (per client address when there is none), answering 429
  beyond that. Override with

      config :escalated, two_factor_rate_limit: %{max_requests: 5, window_ms: 60_000}

  Uses `Escalated.RateLimiter` (or the host's `:rate_limit_backend`).
  """
  @behaviour Plug

  alias Escalated.Plugs.PublicRateLimit

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    config =
      PublicRateLimit.config(:two_factor_rate_limit, %{max_requests: 5, window_ms: 60_000})

    if PublicRateLimit.valid_config?(config) do
      key =
        case conn.assigns[:current_user] do
          %{id: id} when not is_nil(id) -> {:user, to_string(id)}
          _ -> {:ip, Escalated.RateLimiter.client_key(conn.remote_ip)}
        end

      PublicRateLimit.enforce(conn, [
        {:two_factor_verify, key, config.max_requests, config.window_ms}
      ])
    else
      PublicRateLimit.unavailable(conn)
    end
  end
end
