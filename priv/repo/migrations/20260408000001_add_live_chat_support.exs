defmodule Escalated.Repo.Migrations.AddLiveChatSupport do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    # Add chat fields to tickets
    alter table("#{@prefix}tickets") do
      add :channel, :string, size: 16
      add :chat_ended_at, :utc_datetime
      add :chat_metadata, :map, default: %{}
    end

    create index("#{@prefix}tickets", [:channel])

    # Create chat_sessions table
    create table("#{@prefix}chat_sessions") do
      add :ticket_id, references("#{@prefix}tickets", on_delete: :delete_all), null: false
      add :status, :string, size: 32, default: "waiting"
      add :agent_id, :integer
      add :visitor_user_agent, :string
      add :visitor_ip, :string, size: 45
      add :visitor_page_url, :string
      add :agent_joined_at, :utc_datetime
      add :last_activity_at, :utc_datetime
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}chat_sessions", [:status])
    create index("#{@prefix}chat_sessions", [:agent_id])
    create index("#{@prefix}chat_sessions", [:ticket_id])

    # Create chat_routing_rules table
    create table("#{@prefix}chat_routing_rules") do
      add :name, :string, null: false
      add :strategy, :string, size: 32, default: "round_robin"
      add :department_id, references("#{@prefix}departments", on_delete: :nilify_all)
      add :agent_ids, {:array, :integer}, default: []
      add :priority, :integer, default: 0
      add :max_concurrent_chats, :integer, default: 5
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}chat_routing_rules", [:is_active, :priority])
  end
end
