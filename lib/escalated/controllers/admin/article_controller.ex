defmodule Escalated.Controllers.Admin.ArticleController do
  @moduledoc """
  Admin CRUD over knowledge-base articles, with search / status /
  category filtering on the index. Mirrors the Laravel `ArticleController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.{Paginator, UIRenderer}
  alias Escalated.Schemas.{Article, ArticleCategory}

  def index(conn, params) do
    repo = Escalated.repo()

    names = category_names(repo)

    articles =
      Paginator.paginate_query(
        build_query(params),
        repo,
        Map.put_new(params, "per_page", "20"),
        index_path(),
        &article_json(&1, names)
      )

    UIRenderer.render_page(conn, "Escalated/Admin/KnowledgeBase/Articles/Index", %{
      articles: articles,
      categories: categories(repo),
      filters: Map.take(params, ["search", "status", "category_id"])
    })
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/KnowledgeBase/Articles/Form", %{
      article: nil,
      categories: categories(Escalated.repo())
    })
  end

  def edit(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Article, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Article not found"})

      article ->
        UIRenderer.render_page(conn, "Escalated/Admin/KnowledgeBase/Articles/Form", %{
          article: article_json(article, category_names(repo)),
          categories: categories(repo)
        })
    end
  end

  def show(conn, %{"id" => id}) do
    case Escalated.repo().get(Article, id) do
      nil -> conn |> put_status(404) |> json(%{error: "Article not found"})
      article -> json(conn, Article.to_json(article))
    end
  end

  def create(conn, %{"article" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    user = conn.assigns[:current_user]

    %Article{}
    |> Article.changeset(Map.put(params, "author_id", user && user.id))
    |> Escalated.repo().insert()
    |> case do
      {:ok, _} -> conn |> put_flash(:info, "Article created.") |> redirect(to: index_path())
      {:error, cs} -> FormResponse.invalid(conn, cs, index_path() <> "/create")
    end
  end

  def update(conn, %{"id" => id, "article" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case repo.get(Article, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Article not found"})

      article ->
        article
        |> Article.changeset(params)
        |> repo.update()
        |> case do
          {:ok, _} -> conn |> put_flash(:info, "Article updated.") |> redirect(to: index_path())
          {:error, cs} -> FormResponse.invalid(conn, cs, "#{index_path()}/#{id}/edit")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Article, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Article not found"})

      article ->
        repo.delete(article)
        conn |> put_flash(:info, "Article deleted.") |> redirect(to: index_path())
    end
  end

  defp categories(repo) do
    ArticleCategory.ordered() |> repo.all() |> Enum.map(&%{id: &1.id, name: &1.name})
  end

  defp category_names(repo) do
    ArticleCategory |> repo.all() |> Map.new(&{&1.id, &1.name})
  end

  # The pages read `article.category.name`.
  defp article_json(article, names) do
    category =
      case Map.fetch(names, article.category_id) do
        {:ok, name} -> %{id: article.category_id, name: name}
        :error -> nil
      end

    article |> Article.to_json() |> Map.put(:category, category)
  end

  defp build_query(params) do
    Article
    |> filter_search(params["search"])
    |> filter_status(params["status"])
    |> filter_category(params["category_id"])
    |> order_by([a], desc: a.id)
  end

  defp filter_search(query, term) when is_binary(term) and term != "",
    do: Article.search(query, term)

  defp filter_search(query, _), do: query

  defp filter_status(query, status) when is_binary(status) and status != "",
    do: where(query, [a], a.status == ^status)

  defp filter_status(query, _), do: query

  defp filter_category(query, category) when is_binary(category) and category != "",
    do: where(query, [a], a.category_id == ^String.to_integer(category))

  defp filter_category(query, _), do: query

  defp index_path, do: "#{Escalated.config(:route_prefix, "/support")}/admin/kb-articles"
end
