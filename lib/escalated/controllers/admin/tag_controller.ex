defmodule Escalated.Controllers.Admin.TagController do
  @moduledoc """
  Admin controller for managing tags.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Schemas.Tag
  alias Escalated.Rendering.UIRenderer

  def index(conn, _params) do
    repo = Escalated.repo()
    tags = repo.all(Tag.ordered())

    UIRenderer.render_page(conn, "Escalated/Admin/Tags/Index", %{
      tags: Enum.map(tags, &%{id: &1.id, name: &1.name, color: &1.color})
    })
  end

  def show(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Tag, id) do
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Tag not found"})
      tag -> UIRenderer.render_page(conn, "Escalated/Admin/Tags/Show", %{tag: %{id: tag.id, name: tag.name, color: tag.color}})
    end
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Tags/New", %{})
  end

  def create(conn, %{"tag" => params}) do
    repo = Escalated.repo()

    %Tag{}
    |> Tag.changeset(params)
    |> repo.insert()
    |> case do
      {:ok, tag} ->
        conn |> put_flash(:info, "Tag created.") |> redirect(to: admin_tags_path(conn))

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "tag" => params}) do
    repo = Escalated.repo()

    case repo.get(Tag, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Tag not found"})

      tag ->
        tag
        |> Tag.changeset(params)
        |> repo.update()
        |> case do
          {:ok, _} -> conn |> put_flash(:info, "Tag updated.") |> redirect(to: admin_tags_path(conn))
          {:error, cs} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Tag, id) do
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Tag not found"})
      tag ->
        repo.delete(tag)
        conn |> put_flash(:info, "Tag deleted.") |> redirect(to: admin_tags_path(conn))
    end
  end

  defp admin_tags_path(conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/tags"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
