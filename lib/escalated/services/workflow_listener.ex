defmodule Escalated.Services.WorkflowListener do
  @moduledoc """
  Final piece of the workflow stack for Phoenix.

  Provides per-event helper functions that bridge domain events into
  `Escalated.Services.WorkflowRunner.run_for_event/2`. Each helper maps
  an event to a canonical workflow trigger name (matching the 12-event
  set in `Escalated.Services.WorkflowEngine.trigger_events/0`) and
  asynchronously fires the runner via `Task.Supervisor` so a slow
  workflow never blocks the mutation that fired it.

  ## Opt-in wire-up

  Phoenix does not auto-emit ApplicationEvents the way Spring or the
  NestJS EventEmitter2 do, so host applications wire these helpers
  into their `TicketService` overrides or post-write Oban / PubSub
  handlers:

      # After creating a ticket
      WorkflowListener.ticket_created(ticket)

      # After changing status
      WorkflowListener.ticket_status_changed(ticket)

      # After an inbound reply
      WorkflowListener.reply_created(reply)

  ## Failure semantics

  Runner failures are caught inside the spawned task and emitted via
  `Logger.error/1`. They never propagate back to the caller — matching
  the "one bad workflow never blocks the mutation" rule applied
  everywhere else in this stack.

  Mirrors the NestJS workflow.listener.ts, the Spring
  WorkflowListener, and the WordPress WorkflowListener.
  """

  alias Escalated.Services.WorkflowRunner
  require Logger

  @doc """
  Fire the workflow runner for a given trigger / ticket in a
  supervised task. Returns `:ok` immediately; errors are logged.
  """
  @spec fire(String.t(), map()) :: :ok
  def fire(trigger, ticket) when is_binary(trigger) and is_map(ticket) do
    # Unless Task.Supervisor is configured on the host, fall back to a
    # bare Task so this module works in unit tests and in hosts that
    # haven't opted into supervision.
    run_async(fn -> do_fire(trigger, ticket) end)
    :ok
  end

  def fire(_trigger, _ticket), do: :ok

  defp do_fire(trigger, ticket) do
    try do
      WorkflowRunner.run_for_event(trigger, ticket)
    rescue
      e ->
        Logger.error(
          "[WorkflowListener] #{trigger} failed for ticket ##{Map.get(ticket, :id, "?")}: #{Exception.message(e)}"
        )
    end
  end

  defp run_async(fun) do
    case Process.whereis(Escalated.TaskSupervisor) do
      nil -> Task.start(fun)
      _sup -> Task.Supervisor.start_child(Escalated.TaskSupervisor, fun)
    end
  end

  # Per-event helpers — these are the stable API host apps call from
  # their TicketService wrappers. Keeping the mapping in one place
  # mirrors the NestJS switch in workflow.listener.ts.

  @spec ticket_created(map()) :: :ok
  def ticket_created(ticket), do: fire("ticket.created", ticket)

  @spec ticket_updated(map()) :: :ok
  def ticket_updated(ticket), do: fire("ticket.updated", ticket)

  @spec ticket_status_changed(map()) :: :ok
  def ticket_status_changed(ticket), do: fire("ticket.status_changed", ticket)

  @spec ticket_priority_changed(map()) :: :ok
  def ticket_priority_changed(ticket), do: fire("ticket.priority_changed", ticket)

  @spec ticket_assigned(map()) :: :ok
  def ticket_assigned(ticket), do: fire("ticket.assigned", ticket)

  @spec ticket_reopened(map()) :: :ok
  def ticket_reopened(ticket), do: fire("ticket.reopened", ticket)

  @spec ticket_tagged(map()) :: :ok
  def ticket_tagged(ticket), do: fire("ticket.tagged", ticket)

  @spec ticket_department_changed(map()) :: :ok
  def ticket_department_changed(ticket), do: fire("ticket.department_changed", ticket)

  @doc """
  Fire `reply.created` for the ticket the reply belongs to. Takes a
  reply struct with either an embedded `:ticket` or a `:ticket_id`
  that the caller resolves.
  """
  @spec reply_created(map()) :: :ok
  def reply_created(%{ticket: %{} = ticket}), do: fire("reply.created", ticket)
  def reply_created(_), do: :ok

  @spec sla_breached(map()) :: :ok
  def sla_breached(ticket), do: fire("sla.breached", ticket)

  @spec sla_warning(map()) :: :ok
  def sla_warning(ticket), do: fire("sla.warning", ticket)
end
