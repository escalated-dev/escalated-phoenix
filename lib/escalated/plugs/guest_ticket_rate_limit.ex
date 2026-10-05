defmodule Escalated.Plugs.GuestTicketRateLimit do
  @moduledoc "Limits guest ticket creation per IP (see `Escalated.Plugs.GuestSubmissionRateLimit`)."
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: Escalated.Plugs.GuestSubmissionRateLimit.call(conn, :ticket)
end
