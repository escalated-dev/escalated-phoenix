defmodule Escalated.Repo.Migrations.CreateNewsletterSystem do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}newsletter_lists") do
      add :name, :string, null: false
      add :description, :text
      add :kind, :string, null: false, size: 16
      add :filter_json, :map
      add :created_by, :integer

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}newsletter_lists", [:kind])
    create index("#{@prefix}newsletter_lists", [:created_by])

    create table("#{@prefix}newsletter_list_members") do
      add :list_id, references("#{@prefix}newsletter_lists", on_delete: :delete_all), null: false
      add :contact_id, references("#{@prefix}contacts", on_delete: :delete_all), null: false
      add :added_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :added_by, :integer
    end

    create unique_index("#{@prefix}newsletter_list_members", [:list_id, :contact_id])
    create index("#{@prefix}newsletter_list_members", [:contact_id])

    create table("#{@prefix}newsletter_templates") do
      add :name, :string, null: false
      add :theme, :string, null: false, default: "default", size: 64
      add :subject_template, :string, size: 998
      add :body_markdown, :text, null: false
      add :merge_fields_schema, :map
      add :created_by, :integer

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}newsletter_templates", [:theme])
    create index("#{@prefix}newsletter_templates", [:created_by])

    create table("#{@prefix}newsletters") do
      add :subject, :string, null: false, size: 998
      add :from_email, :string, null: false, size: 320
      add :from_name, :string
      add :reply_to, :string, size: 320
      add :target_list_id,
          references("#{@prefix}newsletter_lists", on_delete: :restrict),
          null: false
      add :template_id, references("#{@prefix}newsletter_templates", on_delete: :nilify_all)
      add :theme, :string, size: 64
      add :body_markdown, :text
      add :status, :string, null: false, default: "draft", size: 16
      add :scheduled_at, :utc_datetime
      add :sent_at, :utc_datetime
      add :created_by, :integer
      add :sent_by, :integer
      add :summary_total, :integer, null: false, default: 0
      add :summary_sent, :integer, null: false, default: 0
      add :summary_opened, :integer, null: false, default: 0
      add :summary_clicked, :integer, null: false, default: 0
      add :summary_bounced, :integer, null: false, default: 0
      add :summary_complained, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}newsletters", [:status])
    create index("#{@prefix}newsletters", [:scheduled_at])
    create index("#{@prefix}newsletters", [:status, :scheduled_at])

    create table("#{@prefix}newsletter_deliveries") do
      add :newsletter_id,
          references("#{@prefix}newsletters", on_delete: :delete_all),
          null: false
      add :contact_id, references("#{@prefix}contacts", on_delete: :delete_all), null: false
      add :email_at_send, :string, null: false, size: 320
      add :status, :string, null: false, default: "pending", size: 16
      add :tracking_token, :string, null: false, size: 40
      add :sent_at, :utc_datetime
      add :opened_at, :utc_datetime
      add :last_clicked_at, :utc_datetime
      add :clicks_count, :integer, null: false, default: 0
      add :bounce_reason, :text
      add :failure_reason, :text
      add :attempt_count, :integer, null: false, default: 0
      add :claimed_at, :utc_datetime
      add :is_test, :boolean, null: false, default: false
      add :created_at, :utc_datetime, null: false, default: fragment("NOW()")
    end

    create unique_index("#{@prefix}newsletter_deliveries", [:tracking_token])
    create index("#{@prefix}newsletter_deliveries", [:newsletter_id, :status])
    create index("#{@prefix}newsletter_deliveries", [:contact_id])
    create index("#{@prefix}newsletter_deliveries", [:status, :claimed_at])

    alter table("#{@prefix}contacts") do
      add :marketing_opt_out_at, :utc_datetime
    end

    create index("#{@prefix}contacts", [:marketing_opt_out_at])
  end
end
