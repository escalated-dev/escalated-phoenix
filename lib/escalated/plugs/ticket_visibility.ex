defmodule Escalated.Plugs.TicketVisibility do
  @moduledoc "Installs the authenticated actor for package queries, including widget requests."
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    Escalated.TicketVisibility.put_user(conn.assigns[:current_user])

    register_before_send(conn, fn response ->
      Escalated.TicketVisibility.clear()
      response
    end)
  end
end
