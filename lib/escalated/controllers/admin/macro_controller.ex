defmodule Escalated.Controllers.Admin.MacroController do
  @moduledoc """
  Admin CRUD over Macro definitions.

  The agent-facing apply endpoint lives in
  `Escalated.Controllers.Agent.MacroController`. See
  escalated-developer-context/domain-model/workflows-automations-macros.md.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Schemas.Macro
  alias Escalated.Services.MacroService
  alias Escalated.Rendering.UIRenderer

  def index(conn, _params) do
    repo = Escalated.repo()

    macros =
      Macro
      |> order_by_name()
      |> repo.all()

    UIRenderer.render_page(conn, "Escalated/Admin/Macros/Index", %{
      macros: Enum.map(macros, &Macro.to_json/1)
    })
  end

  def show(conn, %{"id" => id}) do
    case MacroService.find_by_id(Escalated.repo(), id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Macro not found"})

      macro ->
        UIRenderer.render_page(conn, "Escalated/Admin/Macros/Show", %{
          macro: Macro.to_json(macro)
        })
    end
  end

  def create(conn, %{"macro" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    params = stamp_creator(conn, params)

    case MacroService.create(Escalated.repo(), params) do
      {:ok, _macro} ->
        conn |> put_flash(:info, "Macro created.") |> redirect(to: admin_macros_path(conn))

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "macro" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case MacroService.find_by_id(repo, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Macro not found"})

      macro ->
        case MacroService.update(repo, macro, params) do
          {:ok, _} ->
            conn |> put_flash(:info, "Macro updated.") |> redirect(to: admin_macros_path(conn))

          {:error, cs} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case MacroService.find_by_id(repo, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Macro not found"})

      macro ->
        MacroService.delete(repo, macro)
        conn |> put_flash(:info, "Macro deleted.") |> redirect(to: admin_macros_path(conn))
    end
  end

  defp stamp_creator(conn, params) when is_map(params) do
    case current_agent_id(conn) do
      nil -> params
      id -> Map.put(params, "created_by", id)
    end
  end

  defp current_agent_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp order_by_name(query) do
    import Ecto.Query
    from(m in query, order_by: [asc: m.name])
  end

  defp admin_macros_path(_conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/macros"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
