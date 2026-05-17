defmodule Escalated.Schemas.AgentSkill do
  @moduledoc """
  Per-agent proficiency on a skill (host `users.id`, not agent_profile_id).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}agent_skills" do
    field :user_id, :integer
    field :proficiency, :integer, default: 3

    belongs_to :skill, Escalated.Schemas.Skill

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(row, attrs) do
    row
    |> cast(attrs, [:user_id, :skill_id, :proficiency])
    |> validate_required([:user_id, :skill_id])
    |> validate_number(:proficiency, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> validate_number(:user_id, greater_than: 0)
    |> unique_constraint([:user_id, :skill_id])
  end
end
