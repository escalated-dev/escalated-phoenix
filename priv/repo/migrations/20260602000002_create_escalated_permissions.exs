defmodule Escalated.Repo.Migrations.CreateEscalatedPermissions do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}permissions") do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :group, :string
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}permissions", [:slug])
    create index("#{@prefix}permissions", [:group])
  end
end
