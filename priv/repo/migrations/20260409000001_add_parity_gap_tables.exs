defmodule Escalated.Repo.Migrations.AddParityGapTables do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    # Email Channels
    create table("#{@prefix}email_channels") do
      add :email_address, :string, null: false
      add :display_name, :string
      add :department_id, references("#{@prefix}departments", on_delete: :nilify_all)
      add :is_default, :boolean, default: false
      add :is_verified, :boolean, default: false
      add :dkim_status, :string, default: "pending"
      add :dkim_public_key, :text
      add :dkim_selector, :string
      add :reply_to_address, :string
      add :smtp_protocol, :string, default: "tls"
      add :smtp_host, :string
      add :smtp_port, :integer
      add :smtp_username, :string
      add :smtp_password, :string
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}email_channels", [:department_id])
    create index("#{@prefix}email_channels", [:is_active])
    create unique_index("#{@prefix}email_channels", [:email_address])

    # Custom Fields
    create table("#{@prefix}custom_fields") do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :field_type, :string, default: "text"
      add :description, :text
      add :is_required, :boolean, default: false
      add :options, {:array, :string}
      add :default_value, :string
      add :entity_type, :string, default: "ticket"
      add :position, :integer, default: 0
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}custom_fields", [:slug])
    create index("#{@prefix}custom_fields", [:entity_type])

    # Custom Field Values
    create table("#{@prefix}custom_field_values") do
      add :custom_field_id, references("#{@prefix}custom_fields", on_delete: :delete_all), null: false
      add :entity_type, :string, default: "ticket"
      add :entity_id, :integer, null: false
      add :value, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}custom_field_values", [:custom_field_id, :entity_type, :entity_id], name: :unique_field_entity)

    # Custom Objects
    create table("#{@prefix}custom_objects") do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :field_definitions, :map
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}custom_objects", [:slug])

    # Custom Object Records
    create table("#{@prefix}custom_object_records") do
      add :custom_object_id, references("#{@prefix}custom_objects", on_delete: :delete_all), null: false
      add :title, :string
      add :data, :map, default: %{}
      add :linked_entity_type, :string
      add :linked_entity_id, :integer

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}custom_object_records", [:custom_object_id])
    create index("#{@prefix}custom_object_records", [:linked_entity_type, :linked_entity_id])

    # Audit Logs
    create table("#{@prefix}audit_logs") do
      add :action, :string, null: false
      add :entity_type, :string, null: false
      add :entity_id, :integer
      add :performer_type, :string
      add :performer_id, :integer
      add :old_values, :map
      add :new_values, :map
      add :ip_address, :string, size: 45
      add :user_agent, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index("#{@prefix}audit_logs", [:entity_type, :entity_id])
    create index("#{@prefix}audit_logs", [:performer_type, :performer_id])
    create index("#{@prefix}audit_logs", [:inserted_at])

    # Business Schedules
    create table("#{@prefix}business_schedules") do
      add :name, :string, null: false
      add :timezone, :string, default: "UTC"
      add :hours, :map, null: false
      add :is_default, :boolean, default: false
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    # Holidays
    create table("#{@prefix}holidays") do
      add :business_schedule_id, references("#{@prefix}business_schedules", on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :date, :date, null: false
      add :is_recurring, :boolean, default: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index("#{@prefix}holidays", [:business_schedule_id])

    # Two Factors
    create table("#{@prefix}two_factors") do
      add :user_id, :integer, null: false
      add :method, :string, default: "totp"
      add :secret, :string
      add :recovery_codes, {:array, :string}
      add :is_enabled, :boolean, default: false
      add :verified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}two_factors", [:user_id])

    # Workflows
    create table("#{@prefix}workflows") do
      add :name, :string, null: false
      add :description, :text
      add :trigger_event, :string, null: false
      add :conditions, :map, default: %{}
      add :actions, {:array, :map}, default: []
      add :position, :integer, default: 0
      add :is_active, :boolean, default: true
      add :stop_on_match, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}workflows", [:trigger_event])
    create index("#{@prefix}workflows", [:is_active])

    # Workflow Logs
    create table("#{@prefix}workflow_logs") do
      add :workflow_id, :integer, null: false
      add :ticket_id, :integer, null: false
      add :trigger_event, :string, null: false
      add :status, :string, null: false
      add :actions_executed, {:array, :map}, default: []
      add :error_message, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index("#{@prefix}workflow_logs", [:workflow_id])
    create index("#{@prefix}workflow_logs", [:ticket_id])

    # Delayed Actions
    create table("#{@prefix}delayed_actions") do
      add :workflow_id, :integer, null: false
      add :ticket_id, :integer, null: false
      add :action_data, :map, default: %{}
      add :execute_at, :utc_datetime, null: false
      add :executed, :boolean, default: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index("#{@prefix}delayed_actions", [:executed, :execute_at])
  end
end
