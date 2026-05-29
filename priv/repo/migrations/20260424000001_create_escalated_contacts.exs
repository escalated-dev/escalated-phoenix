defmodule Escalated.Repo.Migrations.CreateEscalatedContacts do
  @moduledoc """
  Adds the first-class Contact schema (Pattern B) + nullable
  ticket.contact_id FK. See
  escalated-dev/escalated docs/superpowers/plans/2026-04-24-public-tickets-rollout-status.md.

  Inline guest_name / guest_email / guest_token columns on tickets
  remain for backwards compatibility — a follow-up migration (or
  a mix task) can backfill contact_id from guest_email.
  """
  use Ecto.Migration

  alias Escalated.UserKey

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}contacts") do
      add :email, :string, size: 320, null: false
      add :name, :string
      add :user_id, UserKey.migration_type()
      add :metadata, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}contacts", [:email])
    create index("#{@prefix}contacts", [:user_id])

    alter table("#{@prefix}tickets") do
      add :contact_id, references("#{@prefix}contacts", on_delete: :nilify_all)
    end

    create index("#{@prefix}tickets", [:contact_id])
  end
end
