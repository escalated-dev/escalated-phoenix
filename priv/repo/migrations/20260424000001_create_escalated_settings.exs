defmodule Escalated.Repo.Migrations.CreateEscalatedSettings do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}settings") do
      add :key, :string, null: false
      add :value, :text
      add :group, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}settings", [:key])
    create index("#{@prefix}settings", [:group])
  end
end
