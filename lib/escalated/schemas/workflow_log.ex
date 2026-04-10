defmodule Escalated.Schemas.WorkflowLog do
  @moduledoc """
  Ecto schema for workflow execution logs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}workflow_logs" do
    field :workflow_id, :integer
    field :ticket_id, :integer
    field :trigger_event, :string
    field :status, :string
    field :actions_executed, {:array, :map}, default: []
    field :error_message, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [:workflow_id, :ticket_id, :trigger_event, :status, :actions_executed, :error_message])
    |> validate_required([:workflow_id, :ticket_id, :trigger_event, :status])
  end
end
