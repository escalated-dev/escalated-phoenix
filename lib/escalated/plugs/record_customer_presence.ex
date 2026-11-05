defmodule Escalated.Plugs.RecordCustomerPresence do
  @moduledoc """
  Records that the signed-in customer is on the site, for the agent pages'
  `requester_online` (ADR 2026-11-05-agent-panel-data). At most once every 30
  seconds per customer; staff browsing the customer portal are not recorded,
  and presence never fails the request.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user = conn.assigns[:current_user]

    if user && Map.get(user, :id) && not Escalated.Permissions.agent?(user) do
      Escalated.AgentPanel.quietly(fn -> Escalated.AgentPanel.see_user(user) end)
    end

    conn
  end
end
