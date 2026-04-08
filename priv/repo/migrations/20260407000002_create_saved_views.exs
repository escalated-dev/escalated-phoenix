defmodule Escalated.Repo.Migrations.CreateSavedViews do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}saved_views") do
      add :name, :string, null: false
      add :filters, :map, null: false, default: %{}
      add :user_id, :integer, null: false
      add :is_shared, :boolean, default: false, null: false
      add :position, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}saved_views", [:user_id])
    create index("#{@prefix}saved_views", [:is_shared])
    create unique_index("#{@prefix}saved_views", [:user_id, :name])
  end
end
