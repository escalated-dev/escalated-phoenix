defmodule Escalated.Controllers.Admin.PluginPageController do
  @moduledoc """
  Serves the pages an active plugin declares with `pages/0` as the shared
  `Escalated/Plugin/Page` (plugin contract, "Pages"), at
  `{prefix}/admin/plugins/{slug}/{route}`, behind the admin guard. A page with
  a `capability` the user lacks is a 403; an unknown or inactive plugin, or a
  route it does not declare, is a 404.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Plugins
  alias Escalated.Rendering.UIRenderer

  def show(conn, %{"slug" => slug, "route" => segments}) do
    route = segments |> List.wrap() |> Enum.join("/")
    user = conn.assigns[:current_user]

    case Plugins.find_page(slug, route) do
      {:ok, module, page} ->
        if Plugins.capable?(user, page.capability) do
          UIRenderer.render_page(conn, "Escalated/Plugin/Page", %{
            plugin: slug,
            component: page.component,
            layout: page.layout,
            title: page.title || page.component,
            props: Plugins.page_props(module, page, user)
          })
        else
          conn
          |> put_status(403)
          |> json(%{error: "You do not have the required permission: #{page.capability}"})
        end

      :error ->
        conn |> put_status(404) |> json(%{error: "Not found."})
    end
  end
end
