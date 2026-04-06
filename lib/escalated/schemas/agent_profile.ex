defmodule Escalated.Schemas.AgentProfile do
  @moduledoc """
  Ecto schema for agent-specific profile data (display name, role, etc.).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}agent_profiles" do
    field :user_id, :integer
    field :display_name, :string
    field :role, :string, default: "agent"
    field :is_active, :boolean, default: true
    field :max_tickets, :integer, default: 0
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:user_id, :display_name, :role, :is_active, :max_tickets, :metadata])
    |> validate_required([:user_id])
    |> validate_inclusion(:role, ~w(agent admin))
    |> unique_constraint(:user_id)
  end
end
