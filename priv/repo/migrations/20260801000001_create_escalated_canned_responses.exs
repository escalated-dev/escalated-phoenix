defmodule Escalated.Repo.Migrations.CreateEscalatedCannedResponses do
  use Ecto.Migration

  alias Escalated.UserKey

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}canned_responses") do
      add :title, :string, null: false
      add :body, :text, null: false
      add :category, :string
      add :is_shared, :boolean, null: false, default: true
      add :created_by, UserKey.migration_type()

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}canned_responses", [:is_shared])
    create index("#{@prefix}canned_responses", [:created_by])
  end
end
