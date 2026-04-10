defmodule Escalated.Schemas.Workflow do
  @moduledoc """
  Ecto schema for workflow automation rules.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}workflows" do
    field :name, :string
    field :description, :string
    field :trigger_event, :string
    field :conditions, :map, default: %{}
    field :actions, {:array, :map}, default: []
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true
    field :stop_on_match, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name, :description, :trigger_event, :conditions, :actions, :position, :is_active, :stop_on_match])
    |> validate_required([:name, :trigger_event])
  end

  def active(query \\ __MODULE__) do
    from(w in query, where: w.is_active == true, order_by: [asc: w.position])
  end

  def for_event(query \\ __MODULE__, event) do
    from(w in query, where: w.trigger_event == ^event)
  end
end
