defmodule Escalated.Schemas.Automation do
  @moduledoc """
  Ecto schema for time-based admin automation rules.

  Distinct from `Escalated.Schemas.Workflow` (event-driven) and Macro
  (agent-applied manual). See `escalated-developer-context/domain-model/
  workflows-automations-macros.md` for the canonical taxonomy.

  Matched against open tickets by a recurring scheduler (every 5 min in
  the portfolio convention). Each match has its actions applied.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}automations" do
    field :name, :string
    field :description, :string
    # Conditions: list of %{"field" => ..., "operator" => ..., "value" => ...}
    field :conditions, {:array, :map}, default: []
    # Actions: list of %{"type" => ..., "value" => ...}
    field :actions, {:array, :map}, default: []
    field :active, :boolean, default: true
    field :position, :integer, default: 0
    field :last_run_at, :utc_datetime, default: nil

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(automation, attrs) do
    automation
    |> cast(attrs, [
      :name,
      :description,
      :conditions,
      :actions,
      :active,
      :position,
      :last_run_at
    ])
    |> validate_required([:name])
  end

  def active(query \\ __MODULE__) do
    from(a in query, where: a.active == true, order_by: [asc: a.position, asc: a.id])
  end

  @doc "Serialize an automation row for the admin frontend."
  def to_json(%__MODULE__{} = a) do
    %{
      id: a.id,
      name: a.name,
      description: a.description,
      conditions: a.conditions,
      actions: a.actions,
      active: a.active,
      position: a.position,
      last_run_at: a.last_run_at,
      inserted_at: a.inserted_at,
      updated_at: a.updated_at
    }
  end
end
