defmodule Escalated.Schemas.ArticleTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{Article, ArticleCategory}

  defp repo, do: Escalated.repo()

  defp insert_article!(attrs) do
    {:ok, a} = %Article{} |> Article.changeset(attrs) |> repo().insert()
    a
  end

  describe "Article.changeset/2" do
    test "requires a title and a valid status" do
      refute Article.changeset(%Article{}, %{}).valid?
      refute Article.changeset(%Article{}, %{title: "T", status: "bogus"}).valid?
      assert Article.changeset(%Article{}, %{title: "T", status: "draft"}).valid?
    end

    test "derives a slug from the title when omitted" do
      cs = Article.changeset(%Article{}, %{title: "How To Reset Your Password", status: "draft"})
      assert Ecto.Changeset.get_field(cs, :slug) == "how-to-reset-your-password"
    end

    test "keeps an explicit slug" do
      cs = Article.changeset(%Article{}, %{title: "T", slug: "custom", status: "draft"})
      assert Ecto.Changeset.get_field(cs, :slug) == "custom"
    end

    test "stamps published_at when first published" do
      cs = Article.changeset(%Article{}, %{title: "T", status: "published"})
      assert Ecto.Changeset.get_field(cs, :published_at)
    end

    test "does not stamp published_at for drafts" do
      cs = Article.changeset(%Article{}, %{title: "T", status: "draft"})
      refute Ecto.Changeset.get_field(cs, :published_at)
    end
  end

  describe "scopes" do
    test "published / draft / search filter rows" do
      insert_article!(%{title: "Billing FAQ", status: "published", body: "about invoices"})
      insert_article!(%{title: "Internal note", status: "draft", body: "wip"})

      assert [%{status: "published"}] = Article.published() |> repo().all()
      assert [%{status: "draft"}] = Article.draft() |> repo().all()

      hits = Article |> Article.search("invoices") |> repo().all()
      assert length(hits) == 1
    end
  end

  describe "ArticleCategory" do
    test "auto-slugs and enforces a unique slug" do
      {:ok, _} =
        %ArticleCategory{}
        |> ArticleCategory.changeset(%{name: "Getting Started"})
        |> repo().insert()

      assert {:error, cs} =
               %ArticleCategory{}
               |> ArticleCategory.changeset(%{name: "Getting Started"})
               |> repo().insert()

      refute cs.valid?
    end
  end

  describe "modules load" do
    test "the KB controllers are compiled" do
      assert Code.ensure_loaded?(Escalated.Controllers.Admin.ArticleController)
      assert Code.ensure_loaded?(Escalated.Controllers.Admin.ArticleCategoryController)
    end
  end
end
