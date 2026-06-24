defmodule Escalated.Controllers.Admin.CapacityController do
  @moduledoc """
  Admin view of per-agent capacity + ceiling adjustment. Mirrors the
  Laravel `CapacityController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.AgentCapacity
  alias Escalated.Services.CapacityService

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Capacity/Index", %{
      capacities: Enum.map(CapacityService.all_capacities(), &AgentCapacity.to_json/1)
    })
  end

  def update(conn, %{"id" => id} = params) do
    repo = Escalated.repo()

    case repo.get(AgentCapacity, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Capacity not found"})

      cap ->
        cap
        |> AgentCapacity.changeset(%{max_concurrent: params["max_concurrent"]})
        |> repo.update()
        |> case do
          {:ok, _} ->
            conn |> put_flash(:info, "Capacity updated.") |> redirect(to: capacity_path())

          {:error, changeset} ->
            conn
            |> put_status(422)
            |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
        end
    end
  end

  defp capacity_path do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/capacity"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
