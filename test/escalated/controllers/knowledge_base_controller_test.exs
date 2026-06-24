defmodule Escalated.Controllers.Customer.KnowledgeBaseControllerTest do
  use Escalated.DataCase, async: false

  import Ecto.Query

  alias Escalated.Schemas.Article

  defp repo, do: Escalated.repo()

  defp insert_article!(attrs) do
    {:ok, a} = %Article{} |> Article.changeset(attrs) |> repo().insert()
    a
  end

  test "only published articles are surfaced by the published scope" do
    insert_article!(%{title: "Public", status: "published", body: "x"})
    insert_article!(%{title: "Hidden", status: "draft", body: "y"})

    titles = Article.published() |> repo().all() |> Enum.map(& &1.title)
    assert titles == ["Public"]
  end

  test "view and helpfulness counters increment atomically" do
    article = insert_article!(%{title: "A", status: "published", body: "x"})

    repo().update_all(from(a in Article, where: a.id == ^article.id), inc: [view_count: 1])
    repo().update_all(from(a in Article, where: a.id == ^article.id), inc: [helpful_count: 1])

    reloaded = repo().get(Article, article.id)
    assert reloaded.view_count == 1
    assert reloaded.helpful_count == 1
    assert reloaded.not_helpful_count == 0
  end

  test "the customer knowledge-base controller is compiled" do
    assert Code.ensure_loaded?(Escalated.Controllers.Customer.KnowledgeBaseController)
  end
end
