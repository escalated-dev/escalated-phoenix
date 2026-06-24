defmodule Escalated.Schemas.EscalationRule do
  @moduledoc """
  Ecto schema for escalation rules.

  An escalation rule matches open tickets by `conditions` and applies
  `actions` (escalate, change priority, (re)assign, change department).
  Evaluated by a recurring scheduler via
  `Escalated.Services.EscalationService` — every 5 minutes is the
  portfolio convention. Mirrors the Laravel `EscalationRule` model.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}escalation_rules" do
    field :name, :string
    field :description, :string
    field :trigger_type, :string
    # Conditions: list of %{"field" => ..., "value" => ...}
    field :conditions, {:array, :map}, default: []
    # Actions: list of %{"type" => ..., "value" => ...}
    field :actions, {:array, :map}, default: []
    field :order, :integer, default: 0
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:name, :description, :trigger_type, :conditions, :actions, :order, :is_active])
    |> validate_required([:name])
  end

  def active(query \\ __MODULE__) do
    from(r in query, where: r.is_active == true, order_by: [asc: r.order, asc: r.id])
  end

  @doc "Serialize an escalation rule row for the admin frontend."
  def to_json(%__MODULE__{} = r) do
    %{
      id: r.id,
      name: r.name,
      description: r.description,
      trigger_type: r.trigger_type,
      conditions: r.conditions,
      actions: r.actions,
      order: r.order,
      is_active: r.is_active,
      inserted_at: r.inserted_at,
      updated_at: r.updated_at
    }
  end
end
