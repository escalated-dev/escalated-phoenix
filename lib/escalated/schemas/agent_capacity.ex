defmodule Escalated.Schemas.AgentCapacity do
  @moduledoc """
  Ecto schema for per-agent, per-channel concurrent ticket capacity.

  Tracks how many tickets an agent currently holds (`current_count`)
  against their ceiling (`max_concurrent`) for a given `channel`. Used by
  `Escalated.Services.CapacityService` for load-aware assignment. Mirrors
  the Laravel `AgentCapacity` model (unique per user + channel).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}agent_capacity" do
    field :user_id, @user_id_type
    field :channel, :string, default: "default"
    field :max_concurrent, :integer, default: 10
    field :current_count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(capacity, attrs) do
    capacity
    |> cast(attrs, [:user_id, :channel, :max_concurrent, :current_count])
    |> validate_required([:user_id])
    |> validate_number(:max_concurrent, greater_than_or_equal_to: 0)
    |> validate_number(:current_count, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :channel],
      name: :escalated_agent_capacity_user_id_channel_index
    )
  end

  @doc "Whether the agent can take another ticket on this channel."
  def has_capacity?(%__MODULE__{current_count: current, max_concurrent: max}), do: current < max

  @doc "Current load as a percentage of the ceiling (100.0 when uncapped)."
  def load_percentage(%__MODULE__{max_concurrent: max}) when max <= 0, do: 100.0

  def load_percentage(%__MODULE__{current_count: current, max_concurrent: max}) do
    Float.round(current / max * 100, 1)
  end

  @doc "Serialize a capacity row for the admin frontend."
  def to_json(%__MODULE__{} = cap) do
    %{
      id: cap.id,
      user_id: cap.user_id,
      channel: cap.channel,
      max_concurrent: cap.max_concurrent,
      current_count: cap.current_count,
      load_percentage: load_percentage(cap)
    }
  end
end
