defmodule Escalated.Repo.Migrations.CreateEscalatedTables do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def up do
    # SLA Policies
    create table("#{@prefix}sla_policies") do
      add :name, :string, null: false
      add :description, :text
      add :is_active, :boolean, default: true
      add :is_default, :boolean, default: false
      add :first_response_hours, :map
      add :resolution_hours, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}sla_policies", [:name])

    # Departments
    create table("#{@prefix}departments") do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :email, :string
      add :is_active, :boolean, default: true
      add :default_sla_policy_id, references("#{@prefix}sla_policies", on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}departments", [:name])
    create unique_index("#{@prefix}departments", [:slug])

    # Tags
    create table("#{@prefix}tags") do
      add :name, :string, null: false
      add :color, :string, default: "#6B7280"

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}tags", [:name])

    # Tickets
    create table("#{@prefix}tickets") do
      add :reference, :string
      add :subject, :string, null: false
      add :description, :text, null: false
      add :status, :string, default: "open", null: false
      add :priority, :string, default: "medium", null: false
      add :ticket_type, :string
      add :assigned_to, :integer
      add :requester_id, :integer
      add :requester_type, :string
      add :guest_name, :string
      add :guest_email, :string
      add :guest_token, :string
      add :metadata, :map, default: %{}

      # SLA fields
      add :sla_breached, :boolean, default: false
      add :sla_first_response_due_at, :utc_datetime
      add :sla_resolution_due_at, :utc_datetime
      add :first_response_at, :utc_datetime
      add :resolved_at, :utc_datetime
      add :closed_at, :utc_datetime

      add :department_id, references("#{@prefix}departments", on_delete: :nilify_all)
      add :sla_policy_id, references("#{@prefix}sla_policies", on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}tickets", [:reference])
    create index("#{@prefix}tickets", [:status])
    create index("#{@prefix}tickets", [:priority])
    create index("#{@prefix}tickets", [:assigned_to])
    create index("#{@prefix}tickets", [:department_id])
    create index("#{@prefix}tickets", [:requester_id, :requester_type])
    create index("#{@prefix}tickets", [:sla_breached])
    create index("#{@prefix}tickets", [:inserted_at])

    # Replies
    create table("#{@prefix}replies") do
      add :body, :text, null: false
      add :is_internal, :boolean, default: false
      add :is_system, :boolean, default: false
      add :is_pinned, :boolean, default: false
      add :author_id, :integer

      add :ticket_id, references("#{@prefix}tickets", on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}replies", [:ticket_id])
    create index("#{@prefix}replies", [:author_id])

    # Ticket Activities
    create table("#{@prefix}ticket_activities") do
      add :action, :string, null: false
      add :description, :text
      add :causer_id, :integer
      add :details, :map, default: %{}

      add :ticket_id, references("#{@prefix}tickets", on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index("#{@prefix}ticket_activities", [:ticket_id])

    # Ticket-Tag join table
    create table("#{@prefix}ticket_tags", primary_key: false) do
      add :ticket_id, references("#{@prefix}tickets", on_delete: :delete_all), null: false
      add :tag_id, references("#{@prefix}tags", on_delete: :delete_all), null: false
    end

    create unique_index("#{@prefix}ticket_tags", [:ticket_id, :tag_id])

    # Agent Profiles
    create table("#{@prefix}agent_profiles") do
      add :user_id, :integer, null: false
      add :display_name, :string
      add :role, :string, default: "agent"
      add :is_active, :boolean, default: true
      add :max_tickets, :integer, default: 0
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}agent_profiles", [:user_id])
  end

  def down do
    drop_if_exists table("#{@prefix}ticket_tags")
    drop_if_exists table("#{@prefix}ticket_activities")
    drop_if_exists table("#{@prefix}replies")
    drop_if_exists table("#{@prefix}agent_profiles")
    drop_if_exists table("#{@prefix}tickets")
    drop_if_exists table("#{@prefix}tags")
    drop_if_exists table("#{@prefix}departments")
    drop_if_exists table("#{@prefix}sla_policies")
  end
end
