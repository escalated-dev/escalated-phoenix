defmodule Escalated.Repo.Migrations.CreateSideConversations do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}side_conversations") do
      add :ticket_id, :bigint, null: false
      add :subject, :string, null: false
      add :channel, :string, null: false, default: "internal"
      add :status, :string, null: false, default: "open"
      add :created_by, :bigint

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}side_conversations", [:ticket_id])

    create table("#{@prefix}side_conversation_replies") do
      add :side_conversation_id, :bigint, null: false
      add :body, :text, null: false
      add :author_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}side_conversation_replies", [:side_conversation_id])
  end
end
