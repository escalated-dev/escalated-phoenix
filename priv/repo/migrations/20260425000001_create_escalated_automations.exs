defmodule Escalated.Repo.Migrations.CreateEscalatedAutomations do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}automations") do
      add :name, :string, null: false
      add :description, :text
      add :conditions, :map, default: %{}
      add :actions, {:array, :map}, default: []
      add :active, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      add :last_run_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}automations", [:active])
  end
end
