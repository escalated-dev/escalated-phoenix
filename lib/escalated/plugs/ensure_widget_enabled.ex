defmodule Escalated.Plugs.EnsureWidgetEnabled do
  @moduledoc """
  Refuses public widget requests with 403 while `widget_settings.enabled` is
  false: no codes are sent and no ticket, lookup or chat traffic is served.
  The widget's `/config` route stays available so the embed can see it is off.
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
      |> put_resp_header("cache-control", "no-store")
      |> put_status(403)
      |> Phoenix.Controller.json(%{error: "Widget is disabled"})
      |> halt()
    end
  end

  @doc "Whether the public widget is enabled (`enabled` defaults to true; false or nil turns it off)."
  def enabled? do
    case Escalated.config(:widget_settings, %{}) do
      settings when is_map(settings) -> Map.get(settings, :enabled, true) not in [false, nil]
      _ -> false
    end
  end
end
