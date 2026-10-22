defmodule Escalated.Controllers.KnowledgeBasePagesTest do
  @moduledoc """
  The knowledge base pages, admin and reader, against the props the shared
  Vue pages read and the routes they post to (escalated-laravel's admin
  `ArticleController` / `ArticleCategoryController` and customer
  `KnowledgeBaseController`).
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{Article, ArticleCategory}

  defp repo, do: Escalated.repo()

  setup do
    original = Application.get_env(:escalated, :knowledge_base_enabled)
    Application.put_env(:escalated, :knowledge_base_enabled, true)

    on_exit(fn ->
      if is_nil(original),
        do: Application.delete_env(:escalated, :knowledge_base_enabled),
        else: Application.put_env(:escalated, :knowledge_base_enabled, original)
    end)

    category =
      repo().insert!(
        ArticleCategory.changeset(%ArticleCategory{}, %{name: "Billing", description: "Money"})
      )

    article =
      repo().insert!(
        Article.changeset(%Article{}, %{
          title: "Refunds",
          body: "How refunds work",
          status: "published",
          category_id: category.id,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
      )

    repo().insert!(
      Article.changeset(%Article{}, %{
        title: "Invoices",
        body: "x",
        status: "published",
        category_id: category.id,
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )

    %{
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      customer: host_user!(%{name: "Cy"}),
      category: category,
      article: article
    }
  end

  describe "admin" do
    test "Articles/Index sends a paginator with each article's category", ctx do
      props =
        visit(:get, "/support/admin/kb-articles", ctx.admin)
        |> page!("Escalated/Admin/KnowledgeBase/Articles/Index")

      assert_keys(props, ~w(articles categories filters))
      rows = assert_paginator(props["articles"])
      row = Enum.find(rows, &(&1["title"] == "Refunds"))

      assert_keys(
        row,
        ~w(id title status category view_count helpful_count created_at),
        "article"
      )

      assert row["category"]["name"] == "Billing"
      assert_keys(hd(props["categories"]), ~w(id name), "category")
    end

    test "Articles/Form renders on create and edit", ctx do
      props =
        visit(:get, "/support/admin/kb-articles/create", ctx.admin)
        |> page!("Escalated/Admin/KnowledgeBase/Articles/Form")

      assert_keys(props, ~w(categories))

      props =
        visit(:get, "/support/admin/kb-articles/#{ctx.article.id}/edit", ctx.admin)
        |> page!("Escalated/Admin/KnowledgeBase/Articles/Form")

      assert_keys(props["article"], ~w(id title slug body status category_id), "article")
    end

    test "store and update take the form's body on the page's routes", ctx do
      conn =
        visit(:post, "/support/admin/kb-articles", ctx.admin, %{
          "title" => "Shipping",
          "body" => "Ships fast",
          "status" => "draft",
          "category_id" => ctx.category.id
        })

      assert conn.status in [302, 303]
      article = repo().get_by!(Article, title: "Shipping")

      conn =
        visit(:put, "/support/admin/kb-articles/#{article.id}", ctx.admin, %{
          "title" => "Shipping times",
          "status" => "published"
        })

      assert conn.status in [302, 303]
      assert repo().get!(Article, article.id).title == "Shipping times"

      assert visit(:delete, "/support/admin/kb-articles/#{article.id}", ctx.admin).status in [
               302,
               303
             ]

      assert repo().get(Article, article.id) == nil
    end

    test "an invalid article goes back with errors", ctx do
      conn = visit(:post, "/support/admin/kb-articles", ctx.admin, %{"title" => ""})
      assert conn.status in [302, 303]
    end

    test "Categories/Index lists categories on the page's routes", ctx do
      props =
        visit(:get, "/support/admin/kb-categories", ctx.admin)
        |> page!("Escalated/Admin/KnowledgeBase/Categories/Index")

      assert_keys(
        hd(props["categories"]),
        ~w(id name slug description parent_id position),
        "category"
      )

      conn = visit(:post, "/support/admin/kb-categories", ctx.admin, %{"name" => "Shipping"})
      assert conn.status in [302, 303]
      assert repo().get_by(ArticleCategory, name: "Shipping")
    end
  end

  describe "reader" do
    test "KnowledgeBase/Index sends a paginator and counted categories", ctx do
      props =
        visit(:get, "/support/kb", ctx.customer)
        |> page!("Escalated/Customer/KnowledgeBase/Index")

      assert_keys(props, ~w(articles categories filters feedbackEnabled))
      rows = assert_paginator(props["articles"])
      assert_keys(hd(rows), ~w(id title slug view_count category), "article")
      [category] = props["categories"]
      assert_keys(category, ~w(id name description articles_count), "category")
      assert category["articles_count"] == 2
    end

    test "KnowledgeBase/Article sends the article, related and the feedback flag", ctx do
      props =
        visit(:get, "/support/kb/#{ctx.article.slug}", ctx.customer)
        |> page!("Escalated/Customer/KnowledgeBase/Article")

      assert_keys(props, ~w(article related feedbackEnabled))

      assert_keys(
        props["article"],
        ~w(title body published_at view_count category slug),
        "article"
      )

      assert props["article"]["category"]["name"] == "Billing"
      assert [%{"title" => "Invoices"}] = props["related"]
    end

    test "feedback goes back for an Inertia visit and counts the vote", ctx do
      Application.put_env(:escalated, :knowledge_base_feedback_enabled, true)
      on_exit(fn -> Application.delete_env(:escalated, :knowledge_base_feedback_enabled) end)

      conn =
        visit(:post, "/support/kb/#{ctx.article.slug}/feedback", ctx.customer, %{
          "helpful" => true
        })

      assert conn.status in [302, 303]
      assert repo().get!(Article, ctx.article.id).helpful_count == 1
    end
  end
end
