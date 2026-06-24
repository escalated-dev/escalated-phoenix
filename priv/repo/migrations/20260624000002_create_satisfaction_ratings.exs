defmodule Escalated.Repo.Migrations.CreateSatisfactionRatings do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}satisfaction_ratings") do
      add :ticket_id, :bigint, null: false
      add :rating, :integer, null: false
      add :comment, :text
      add :rated_by_type, :string
      add :rated_by_id, :bigint
      add :created_at, :utc_datetime
    end

    create unique_index("#{@prefix}satisfaction_ratings", [:ticket_id])
  end
end
