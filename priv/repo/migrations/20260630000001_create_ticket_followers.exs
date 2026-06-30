defmodule Escalated.Repo.Migrations.CreateTicketFollowers do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}ticket_followers") do
      add :ticket_id, :bigint, null: false
      add :user_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}ticket_followers", [:ticket_id, :user_id])
    create index("#{@prefix}ticket_followers", [:user_id])
  end
end
