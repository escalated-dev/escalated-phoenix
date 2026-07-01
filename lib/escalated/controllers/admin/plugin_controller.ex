defmodule Escalated.Controllers.Admin.PluginController do
  @moduledoc """
  Admin management of host-registered plugins: list them with activation state
  and toggle activate / deactivate / uninstall. Mirrors the Laravel
  `PluginController`, minus the ZIP-upload endpoint — on the BEAM, plugins are
  compiled host modules registered in config rather than uploaded files.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Plugins
  alias Escalated.Rendering.UIRenderer

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Plugins/Index", %{
      plugins: Plugins.all()
    })
  end

  def activate(conn, %{"slug" => slug}) do
    respond(conn, Plugins.activate(slug), "Plugin activated.")
  end

  def deactivate(conn, %{"slug" => slug}) do
    respond(conn, Plugins.deactivate(slug), "Plugin deactivated.")
  end

  def delete(conn, %{"slug" => slug}) do
    respond(conn, Plugins.delete(slug), "Plugin uninstalled.")
  end

  defp respond(conn, {:ok, _}, message) do
    conn |> put_flash(:info, message) |> redirect(to: index_path())
  end

  defp respond(conn, {:error, :not_found}, _message) do
    conn |> put_status(404) |> json(%{error: "Plugin not found."})
  end

  defp respond(conn, {:error, _reason}, _message) do
    conn |> put_status(422) |> json(%{error: "Could not update plugin."})
  end

  defp index_path do
    "#{Escalated.config(:route_prefix, "/support")}/admin/plugins"
  end
end
