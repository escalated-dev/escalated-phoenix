defmodule Escalated.Repo.Migrations.CreateEscalatedSkillsManagement do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table("#{@prefix}skills") do
      add :name, :string, null: false, size: 100
      add :slug, :string, null: false, size: 100
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}skills", [:slug])
    create unique_index("#{@prefix}skills", [:name])

    create table("#{@prefix}skill_routing_tags") do
      add :skill_id, references("#{@prefix}skills", on_delete: :delete_all), null: false
      add :tag_id, references("#{@prefix}tags", on_delete: :delete_all), null: false
    end

    create unique_index("#{@prefix}skill_routing_tags", [:skill_id, :tag_id])

    create table("#{@prefix}skill_routing_departments") do
      add :skill_id, references("#{@prefix}skills", on_delete: :delete_all), null: false

      add :department_id, references("#{@prefix}departments", on_delete: :delete_all), null: false
    end

    create unique_index("#{@prefix}skill_routing_departments", [:skill_id, :department_id])

    create table("#{@prefix}agent_skills") do
      add :user_id, :integer, null: false
      add :skill_id, references("#{@prefix}skills", on_delete: :delete_all), null: false
      add :proficiency, :integer, null: false, default: 3

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}agent_skills", [:user_id, :skill_id])
    create index("#{@prefix}agent_skills", [:skill_id])
    create index("#{@prefix}agent_skills", [:user_id])
  end
end
