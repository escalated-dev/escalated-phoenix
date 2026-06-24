defmodule Escalated.Repo.Migrations.CreateAgentCapacity do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}agent_capacity") do
      add :user_id, :bigint, null: false
      add :channel, :string, null: false, default: "default"
      add :max_concurrent, :integer, null: false, default: 10
      add :current_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}agent_capacity", [:user_id, :channel])
    create index("#{@prefix}agent_capacity", [:user_id])
  end
end
