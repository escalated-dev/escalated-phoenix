defmodule Escalated.Controllers.Customer.KnowledgeBaseController do
  @moduledoc """
  Customer-facing knowledge base: browse/search published articles, read
  an article (incrementing its view count), and submit helpful /
  not-helpful feedback. Mirrors the Laravel customer `KnowledgeBaseController`.

  Route-level access is gated by `Escalated.Plugs.EnsureKbEnabled`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{Article, ArticleCategory}

  def index(conn, params) do
    repo = Escalated.repo()

    UIRenderer.render_page(conn, "Escalated/Customer/KnowledgeBase/Index", %{
      categories: category_tree(repo),
      articles: Enum.map(published_articles(repo, params), &Article.to_json/1),
      filters: Map.take(params, ["search", "category"]),
      feedback_enabled: feedback_enabled?()
    })
  end

  def show(conn, %{"slug" => slug}) do
    repo = Escalated.repo()

    case repo.one(from(a in Article.published(), where: a.slug == ^slug)) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Article not found"})

      article ->
        increment_views(repo, article.id)

        UIRenderer.render_page(conn, "Escalated/Customer/KnowledgeBase/Article", %{
          article: Article.to_json(%{article | view_count: article.view_count + 1}),
          related: related_articles(repo, article),
          feedback_enabled: feedback_enabled?()
        })
    end
  end

  def feedback(conn, %{"slug" => slug} = params) do
    repo = Escalated.repo()

    cond do
      not feedback_enabled?() -> conn |> put_status(404) |> json(%{error: "Not found"})
      true -> record_feedback(conn, repo, slug, params)
    end
  end

  defp record_feedback(conn, repo, slug, params) do
    case repo.one(from(a in Article.published(), where: a.slug == ^slug)) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Article not found"})

      article ->
        field = if truthy?(params["helpful"]), do: :helpful_count, else: :not_helpful_count
        repo.update_all(from(a in Article, where: a.id == ^article.id), inc: [{field, 1}])
        conn |> put_flash(:info, "Thank you for your feedback!") |> json(%{ok: true})
    end
  end

  defp category_tree(repo) do
    counts = published_counts(repo)

    ArticleCategory.roots()
    |> ArticleCategory.ordered()
    |> repo.all()
    |> Enum.map(fn category ->
      category
      |> ArticleCategory.to_json()
      |> Map.put(:article_count, Map.get(counts, category.id, 0))
    end)
  end

  defp published_counts(repo) do
    from(a in Article,
      where: a.status == "published" and not is_nil(a.category_id),
      group_by: a.category_id,
      select: {a.category_id, count(a.id)}
    )
    |> repo.all()
    |> Map.new()
  end

  defp published_articles(repo, params) do
    Article.published()
    |> maybe_search(params["search"])
    |> maybe_category(params["category"])
    |> order_by([a], desc: a.published_at)
    |> repo.all()
  end

  defp maybe_search(query, term) when is_binary(term) and term != "",
    do: Article.search(query, term)

  defp maybe_search(query, _), do: query

  defp maybe_category(query, category) when is_binary(category) and category != "",
    do: where(query, [a], a.category_id == ^String.to_integer(category))

  defp maybe_category(query, _), do: query

  defp related_articles(_repo, %Article{category_id: nil}), do: []

  defp related_articles(repo, article) do
    repo.all(
      from(a in Article.published(),
        where: a.category_id == ^article.category_id and a.id != ^article.id,
        limit: 5,
        select: %{id: a.id, title: a.title, slug: a.slug}
      )
    )
  end

  defp increment_views(repo, id) do
    repo.update_all(from(a in Article, where: a.id == ^id), inc: [view_count: 1])
  end

  defp feedback_enabled?, do: Escalated.config(:knowledge_base_feedback_enabled, true)

  defp truthy?(value), do: value in [true, "true", "1", 1]
end
