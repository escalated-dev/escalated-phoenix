defmodule Escalated.Controllers.Agent.SavedViewController do
  @moduledoc """
  Agent-facing controller for managing saved views (custom queues).
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Services.SavedViewService
  alias Escalated.Rendering.UIRenderer

  def index(conn, _params) do
    user = conn.assigns[:current_user]
    views = SavedViewService.list_for_user(user.id)

    UIRenderer.render_json(conn, %{saved_views: Enum.map(views, &view_json/1)})
  end

  def create(conn, %{"saved_view" => attrs}) do
    user = conn.assigns[:current_user]

    attrs = Map.put(attrs, "user_id", user.id)

    case SavedViewService.create(atomize_keys(attrs)) do
      {:ok, view} ->
        conn
        |> put_status(201)
        |> Phoenix.Controller.json(%{saved_view: view_json(view)})

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    case SavedViewService.find(id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Saved view not found"})

      view ->
        Phoenix.Controller.json(conn, %{saved_view: view_json(view)})
    end
  end

  def update(conn, %{"id" => id, "saved_view" => attrs}) do
    user = conn.assigns[:current_user]

    case SavedViewService.find(id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Saved view not found"})

      view ->
        case SavedViewService.update(view, atomize_keys(attrs), actor_id: user.id) do
          {:ok, updated} ->
            Phoenix.Controller.json(conn, %{saved_view: view_json(updated)})

          {:error, :unauthorized} ->
            conn |> put_status(403) |> Phoenix.Controller.json(%{error: "Not authorized"})

          {:error, changeset} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns[:current_user]

    case SavedViewService.find(id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Saved view not found"})

      view ->
        case SavedViewService.delete(view, actor_id: user.id) do
          {:ok, _} ->
            Phoenix.Controller.json(conn, %{message: "Saved view deleted."})

          {:error, :unauthorized} ->
            conn |> put_status(403) |> Phoenix.Controller.json(%{error: "Not authorized"})

          {:error, _} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{error: "Could not delete saved view"})
        end
    end
  end

  # Private

  defp view_json(view) do
    %{
      id: view.id,
      name: view.name,
      filters: view.filters,
      user_id: view.user_id,
      is_shared: view.is_shared,
      position: view.position,
      created_at: view.inserted_at && DateTime.to_iso8601(view.inserted_at),
      updated_at: view.updated_at && DateTime.to_iso8601(view.updated_at)
    }
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, val} when is_binary(key) -> {String.to_atom(key), val}
      {key, val} -> {key, val}
    end)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
