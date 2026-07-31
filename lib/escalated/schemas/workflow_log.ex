defmodule Escalated.Schemas.WorkflowLog do
  @moduledoc """
  Ecto schema for workflow execution logs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}workflow_logs" do
    belongs_to :workflow, Escalated.Schemas.Workflow
    belongs_to :ticket, Escalated.Schemas.Ticket
    field :trigger_event, :string
    field :conditions_matched, :boolean, default: true
    field :actions_executed, {:array, :map}, default: []
    field :error_message, :string
    field :status, :string
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :workflow_id,
      :ticket_id,
      :trigger_event,
      :conditions_matched,
      :actions_executed,
      :error_message,
      :status,
      :started_at,
      :completed_at
    ])
    |> validate_required([:workflow_id, :ticket_id, :trigger_event])
  end

  @doc "Serialize a workflow log with computed fields expected by the frontend."
  def to_json(%__MODULE__{} = log) do
    actions = log.actions_executed || []

    duration_ms =
      if log.started_at && log.completed_at do
        DateTime.diff(log.completed_at, log.started_at, :millisecond)
      else
        nil
      end

    %{
      id: log.id,
      workflow_id: log.workflow_id,
      ticket_id: log.ticket_id,
      trigger_event: log.trigger_event,
      event: log.trigger_event,
      workflow_name: get_in_assoc(log, [:workflow, :name]),
      ticket_reference: get_in_assoc(log, [:ticket, :reference]),
      matched: log.conditions_matched,
      actions_executed: length(actions),
      action_details: actions,
      duration_ms: duration_ms,
      status:
        log.status ||
          if(log.error_message && log.error_message != "", do: "failed", else: "success"),
      error_message: log.error_message,
      created_at: log.inserted_at
    }
  end

  defp get_in_assoc(struct, [key | rest]) do
    case Map.get(struct, key) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      value when rest == [] -> value
      value -> get_in_assoc(value, rest)
    end
  end
end
