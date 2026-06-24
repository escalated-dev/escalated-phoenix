defmodule Escalated.Controllers.Admin.ArticleCategoryController do
  @moduledoc """
  Admin CRUD over knowledge-base article categories. Mirrors the Laravel
  `ArticleCategoryController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.ArticleCategory

  def index(conn, _params) do
    categories =
      ArticleCategory.ordered()
      |> Escalated.repo().all()
      |> Enum.map(&ArticleCategory.to_json/1)

    UIRenderer.render_page(conn, "Escalated/Admin/KnowledgeBase/Categories/Index", %{
      categories: categories
    })
  end

  def create(conn, %{"category" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    %ArticleCategory{}
    |> ArticleCategory.changeset(params)
    |> Escalated.repo().insert()
    |> case do
      {:ok, _} -> conn |> put_flash(:info, "Category created.") |> redirect(to: index_path())
      {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
    end
  end

  def update(conn, %{"id" => id, "category" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case repo.get(ArticleCategory, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Category not found"})

      category ->
        category
        |> ArticleCategory.changeset(params)
        |> repo.update()
        |> case do
          {:ok, _} -> conn |> put_flash(:info, "Category updated.") |> redirect(to: index_path())
          {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(ArticleCategory, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Category not found"})

      category ->
        repo.delete(category)
        conn |> put_flash(:info, "Category deleted.") |> redirect(to: index_path())
    end
  end

  defp index_path, do: "#{Escalated.config(:route_prefix, "/support")}/admin/kb/categories"

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
