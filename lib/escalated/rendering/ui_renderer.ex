defmodule Escalated.Rendering.UIRenderer do
  @moduledoc """
  Renderer abstraction for Escalated controllers.

  By default uses Inertia.js (via the `inertia` package). Falls back to JSON
  if Inertia is not available or UI is disabled.

  Controllers call `render_page/3` instead of directly coupling to a
  rendering strategy.
  """

  @doc """
  Renders a page using the configured rendering strategy.

  - If `inertia` is loaded and UI is enabled, renders an Inertia page.
  - Otherwise, renders JSON.
  """
  def render_page(conn, component, props) do
    if inertia_available?() && Escalated.config(:ui_enabled, true) do
      render_inertia(conn, component, props)
    else
      render_json(conn, props)
    end
  end

  @doc """
  Always renders JSON, regardless of UI config.
  """
  def render_json(conn, data) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Phoenix.Controller.json(data)
  end

  defp render_inertia(conn, component, props) do
    if Code.ensure_loaded?(Inertia.Controller) do
      # Props are passed as a MAP, not `props: props`. render_inertia/3 treats a
      # list third argument as options, so the old keyword form would render the
      # page with no props at all rather than raising.
      apply(Inertia.Controller, :render_inertia, [conn, component, Map.new(props)])
    else
      render_json(conn, props)
    end
  end

  defp inertia_available? do
    Code.ensure_loaded?(Inertia)
  end
end
