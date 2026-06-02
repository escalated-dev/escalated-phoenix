defmodule Escalated.Plugs.EnsureNewslettersEnabled do
  @moduledoc """
  Returns 404 when `:enable_newsletters` is false.
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if enabled?() do
      conn
    else
      conn
      |> put_status(404)
      |> Phoenix.Controller.text("Not Found")
      |> halt()
    end
  end

  defp enabled? do
    Application.get_env(:escalated, :enable_newsletters, false) in [true, "true", 1, "1"]
  end
end
