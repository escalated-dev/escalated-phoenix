defmodule Escalated.Services.RuleActions do
  @moduledoc false
  # Ticket field changes made by escalation rules, automations and macros.
  #
  # Each goes through `TicketService` / `AssignmentService` -- never a raw
  # `Ticket.changeset |> repo.update` -- so the same activity rows, hooks,
  # webhooks, workflows and assignment-eligibility checks run as when an agent
  # makes the change by hand. A change to the value the ticket already has is a
  # no-op, so a rule that matches on every run does not repeat its events.
  #
  # Every function returns `{:ok, ticket}` with the current ticket, or
  # `{:error, reason}`.

  alias Escalated.Schemas.{Department, Ticket}
  alias Escalated.Services.{AssignmentService, TicketService}

  def change_status(%Ticket{} = ticket, value, opts \\ []) do
    status = to_string(value)

    if ticket.status == status,
      do: {:ok, ticket},
      else: TicketService.transition_status(ticket, status, opts)
  end

  def change_priority(%Ticket{} = ticket, value, opts \\ []) do
    priority = to_string(value)

    if ticket.priority == priority,
      do: {:ok, ticket},
      else: TicketService.change_priority(ticket, priority, opts)
  end

  def assign(ticket, value, opts \\ [])

  def assign(%Ticket{assigned_to: nil} = ticket, value, _opts) when value in [nil, ""],
    do: {:ok, ticket}

  def assign(%Ticket{} = ticket, value, opts) when value in [nil, ""],
    do: AssignmentService.unassign(ticket, opts)

  def assign(%Ticket{} = ticket, value, opts) do
    if to_string(ticket.assigned_to) == to_string(value),
      do: {:ok, ticket},
      else: AssignmentService.assign(ticket, value, opts)
  end

  def change_department(%Ticket{} = ticket, value, opts \\ []) do
    case Escalated.repo().get(Department, to_int(value)) do
      nil ->
        {:error, :department_not_found}

      %Department{id: id} when id == ticket.department_id ->
        {:ok, ticket}

      %Department{} = department ->
        TicketService.change_department(ticket, department, opts)
    end
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(String.trim(v))
  defp to_int(v), do: raise(ArgumentError, "invalid department id: #{inspect(v)}")
end
