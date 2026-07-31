defmodule Escalated.Repo.Migrations.CreateEscalatedWebhooks do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}webhooks") do
      add :url, :string, null: false
      add :events, {:array, :string}, null: false, default: []
      add :secret, :string
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create table("#{@prefix}webhook_deliveries") do
      add :webhook_id, references("#{@prefix}webhooks", on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :payload, :map
      add :response_code, :integer
      add :response_body, :text
      add :attempts, :integer, null: false, default: 0
      add :delivered_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}webhook_deliveries", [:webhook_id])
    create index("#{@prefix}webhook_deliveries", [:event])
  end
end
