defmodule Escalated.Repo.Migrations.CreateKnowledgeBase do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}article_categories") do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :parent_id, :bigint
      add :position, :integer, null: false, default: 0
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}article_categories", [:slug])

    create table("#{@prefix}articles") do
      add :category_id, :bigint
      add :title, :string, null: false
      add :slug, :string, null: false
      add :body, :text
      add :status, :string, null: false, default: "draft"
      add :author_id, :bigint
      add :view_count, :integer, null: false, default: 0
      add :helpful_count, :integer, null: false, default: 0
      add :not_helpful_count, :integer, null: false, default: 0
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}articles", [:slug])
    create index("#{@prefix}articles", [:category_id])
    create index("#{@prefix}articles", [:status])
  end
end
