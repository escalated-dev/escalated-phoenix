defmodule Escalated.Repo.Migrations.CreateTicketLinks do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}ticket_links") do
      add :parent_ticket_id, :bigint, null: false
      add :child_ticket_id, :bigint, null: false
      add :link_type, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}ticket_links", [
             :parent_ticket_id,
             :child_ticket_id,
             :link_type
           ])

    create index("#{@prefix}ticket_links", [:parent_ticket_id])
    create index("#{@prefix}ticket_links", [:child_ticket_id])
  end
end
