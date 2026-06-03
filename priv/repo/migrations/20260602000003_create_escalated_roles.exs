defmodule Escalated.Repo.Migrations.CreateEscalatedRoles do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}roles") do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :is_system, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}roles", [:slug])

    create table("#{@prefix}role_permissions", primary_key: false) do
      add :role_id, references("#{@prefix}roles", on_delete: :delete_all), null: false
      add :permission_id, references("#{@prefix}permissions", on_delete: :delete_all), null: false
    end

    create unique_index("#{@prefix}role_permissions", [:role_id, :permission_id])
    create index("#{@prefix}role_permissions", [:permission_id])
  end
end
