defmodule Escalated.Plugs.GuestRateLimit do
  @moduledoc "Throttles anonymous ticket creation, lookup and guest ratings."
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Escalated.Plugs.PublicRateLimit.call(conn, bucket: :guest, config: :guest_rate_limit)
  end
end
