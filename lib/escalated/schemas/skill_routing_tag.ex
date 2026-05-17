defmodule Escalated.Schemas.SkillRoutingTag do
  @moduledoc """
  Join between a skill and a ticket tag for explicit routing.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}skill_routing_tags" do
    belongs_to :skill, Escalated.Schemas.Skill
    belongs_to :tag, Escalated.Schemas.Tag
  end

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:skill_id, :tag_id])
    |> validate_required([:skill_id, :tag_id])
    |> foreign_key_constraint(:skill_id)
    |> foreign_key_constraint(:tag_id)
    |> unique_constraint([:skill_id, :tag_id])
  end
end
