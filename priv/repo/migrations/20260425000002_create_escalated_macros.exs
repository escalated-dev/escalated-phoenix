defmodule Escalated.Repo.Migrations.CreateEscalatedMacros do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}macros") do
      add :name, :string, null: false
      add :description, :text
      add :actions, {:array, :map}, default: []
      add :is_shared, :boolean, null: false, default: true
      add :created_by, :integer

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}macros", [:is_shared])
    create index("#{@prefix}macros", [:created_by])
  end
end
