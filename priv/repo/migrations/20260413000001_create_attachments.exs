defmodule Escalated.Repo.Migrations.CreateAttachments do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}attachments") do
      add :original_filename, :string, null: false
      add :mime_type, :string
      add :size, :integer
      add :storage_key, :string, null: false
      add :storage_backend, :string, default: "local"

      add :ticket_id, references("#{@prefix}tickets", on_delete: :delete_all)
      add :reply_id, references("#{@prefix}replies", on_delete: :delete_all)
      add :uploaded_by, :integer

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}attachments", [:ticket_id])
    create index("#{@prefix}attachments", [:reply_id])
  end
end
