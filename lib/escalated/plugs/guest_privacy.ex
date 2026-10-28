defmodule Escalated.Plugs.GuestPrivacy do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> headers()
    # Set again just before sending, so a later plug that answers on its own
    # (a rate-limit 429 sets `cache-control: no-store`) still sends these.
    |> register_before_send(&headers/1)
  end

  defp headers(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
