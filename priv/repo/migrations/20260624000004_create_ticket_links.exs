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

    # Named explicitly. The name Ecto would derive is 71 characters, and
    # PostgreSQL truncates identifiers at 63 bytes -- so the index on disk was
    # called something no changeset could match, and a duplicate link raised
    # instead of failing validation.
    create unique_index(
             "#{@prefix}ticket_links",
             [:parent_ticket_id, :child_ticket_id, :link_type],
             name: "#{@prefix}ticket_links_unique"
           )

    create index("#{@prefix}ticket_links", [:parent_ticket_id])
    create index("#{@prefix}ticket_links", [:child_ticket_id])
  end
end
