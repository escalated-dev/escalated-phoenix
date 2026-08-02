defmodule Escalated.Repo.Migrations.CreateEscalatedMentions do
  use Ecto.Migration

  alias Escalated.UserKey

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}mentions") do
      add :reply_id, references("#{@prefix}replies", on_delete: :delete_all), null: false
      # No DB-level FK to the host `users` table — the host owns it and may key
      # on uuid/string. Mirrors the reply `author_id` / follower `user_id`
      # convention. See escalated-laravel mentions migration (#88).
      add :user_id, UserKey.migration_type(), null: false
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}mentions", [:reply_id, :user_id])
    create index("#{@prefix}mentions", [:user_id])
  end
end
