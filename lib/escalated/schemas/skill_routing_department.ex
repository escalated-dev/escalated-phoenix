defmodule Escalated.Schemas.SkillRoutingDepartment do
  @moduledoc """
  Join between a skill and a department for explicit routing.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}skill_routing_departments" do
    belongs_to :skill, Escalated.Schemas.Skill
    belongs_to :department, Escalated.Schemas.Department
  end

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:skill_id, :department_id])
    |> validate_required([:skill_id, :department_id])
    |> foreign_key_constraint(:skill_id)
    |> foreign_key_constraint(:department_id)
    |> unique_constraint([:skill_id, :department_id])
  end
end
