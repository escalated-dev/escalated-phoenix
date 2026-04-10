defmodule Escalated.Schemas.DelayedAction do
  @moduledoc """
  Ecto schema for delayed workflow actions scheduled for future execution.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}delayed_actions" do
    field :workflow_id, :integer
    field :ticket_id, :integer
    field :action_data, :map, default: %{}
    field :execute_at, :utc_datetime
    field :executed, :boolean, default: false

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(delayed_action, attrs) do
    delayed_action
    |> cast(attrs, [:workflow_id, :ticket_id, :action_data, :execute_at, :executed])
    |> validate_required([:workflow_id, :ticket_id, :execute_at])
  end

  def pending(query \\ __MODULE__) do
    now = DateTime.utc_now()
    from(d in query, where: d.executed == false and d.execute_at <= ^now)
  end
end
