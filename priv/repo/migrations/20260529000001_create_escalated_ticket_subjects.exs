defmodule Escalated.Repo.Migrations.CreateEscalatedTicketSubjects do
  @moduledoc """
  Ticket subjects — host-app entities a ticket is *about* (Project, Customer, …),
  distinct from the requester and the subject line. `subject_id` is a plain string
  so integer, UUID, and other host primary key types all work.
  """
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}ticket_subjects") do
      add :ticket_id, references("#{@prefix}tickets", on_delete: :delete_all), null: false
      add :subject_type, :string, null: false
      add :subject_id, :string, null: false
      add :role, :string
      add :position, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}ticket_subjects", [:ticket_id, :subject_type, :subject_id],
             name: :escalated_ticket_subject_unique
           )

    create index("#{@prefix}ticket_subjects", [:subject_type, :subject_id])
  end
end
