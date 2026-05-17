defmodule Escalated.Schemas.Skill do
  @moduledoc """
  Admin-defined capability label used for agent routing.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}skills" do
    field :name, :string
    field :slug, :string
    field :description, :string

    has_many :skill_routing_tags, Escalated.Schemas.SkillRoutingTag
    has_many :skill_routing_departments, Escalated.Schemas.SkillRoutingDepartment
    has_many :agent_skills, Escalated.Schemas.AgentSkill

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(skill, attrs) do
    skill
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> put_slug_from_name()
    |> validate_length(:slug, max: 100)
    |> unique_constraint(:slug)
    |> unique_constraint(:name)
  end

  defp put_slug_from_name(changeset) do
    case get_field(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :slug, slugify(name))
    end
  end

  defp slugify(name) do
    name
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> then(fn s -> if s == "", do: "skill", else: s end)
  end
end
