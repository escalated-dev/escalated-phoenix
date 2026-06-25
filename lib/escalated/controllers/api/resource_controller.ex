defmodule Escalated.Controllers.Api.ResourceController do
  @moduledoc """
  Public JSON reference endpoints for API clients (the Flutter app and any
  integration): published knowledge-base articles + categories, departments,
  and tags. Part of the general `/api/v1` surface.
  """
  use Phoenix.Controller, formats: [:json]
  import Ecto.Query

  alias Escalated.Schemas.{Article, ArticleCategory, Department, Tag}

  def kb_articles(conn, params) do
    repo = Escalated.repo()

    query =
      case params["search"] do
        term when is_binary(term) and term != "" -> Article.search(Article.published(), term)
        _ -> Article.published()
      end

    articles = repo.all(from(a in query, order_by: [desc: a.published_at]))
    json(conn, %{data: Enum.map(articles, &Article.to_json/1)})
  end

  def kb_categories(conn, _params) do
    categories = ArticleCategory.ordered() |> Escalated.repo().all()
    json(conn, %{data: Enum.map(categories, &ArticleCategory.to_json/1)})
  end

  def departments(conn, _params) do
    departments =
      Department.active() |> Department.ordered() |> Escalated.repo().all()

    json(conn, %{data: Enum.map(departments, &%{id: &1.id, name: &1.name})})
  end

  def tags(conn, _params) do
    tags = Escalated.repo().all(from(t in Tag, order_by: [asc: t.name]))
    json(conn, %{data: Enum.map(tags, &%{id: &1.id, name: &1.name})})
  end
end
