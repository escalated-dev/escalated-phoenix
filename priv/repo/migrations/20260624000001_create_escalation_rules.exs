defmodule Escalated.Repo.Migrations.CreateEscalationRules do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}escalation_rules") do
      add :name, :string, null: false
      add :description, :text
      add :trigger_type, :string
      add :conditions, :map
      add :actions, :map
      add :order, :integer, null: false, default: 0
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}escalation_rules", [:is_active])
  end
end
