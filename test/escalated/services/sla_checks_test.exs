defmodule Escalated.Services.SlaChecksTest do
  @moduledoc """
  The scheduled SLA checks: breaches past a deadline, warnings ahead of one.

  `SlaService.check_breaches/0` had no caller, and nothing computed a warning,
  so `sla.breached` and `sla.warning` -- both offered on the webhook screen --
  could not fire in an install that follows the documented mix tasks.
  """
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.{SlaService, TicketService}

  defp repo, do: Escalated.repo()

  defp ticket!(attrs) do
    {:ok, ticket} =
      TicketService.create(Map.merge(%{subject: "Printer", description: "Jammed"}, attrs))

    ticket
  end

  defp minutes_from_now(minutes) do
    DateTime.utc_now() |> DateTime.add(minutes * 60, :second) |> DateTime.truncate(:second)
  end

  test "check_breaches flags open tickets past their first-response deadline" do
    overdue = ticket!(%{sla_first_response_due_at: minutes_from_now(-5)})
    on_time = ticket!(%{sla_first_response_due_at: minutes_from_now(120)})

    assert Enum.map(SlaService.check_breaches(), & &1.id) == [overdue.id]
    assert repo().get!(Ticket, overdue.id).sla_breached
    refute repo().get!(Ticket, on_time.id).sla_breached
  end

  test "check_warnings returns tickets due inside the window and no others" do
    due_soon = ticket!(%{sla_first_response_due_at: minutes_from_now(10)})
    ticket!(%{sla_first_response_due_at: minutes_from_now(120)})
    ticket!(%{sla_first_response_due_at: minutes_from_now(-5)})

    ticket!(%{
      sla_first_response_due_at: minutes_from_now(10),
      first_response_at: minutes_from_now(-1)
    })

    resolution_soon = ticket!(%{sla_resolution_due_at: minutes_from_now(20)})

    warned = SlaService.check_warnings(30) |> Enum.map(& &1.id) |> Enum.sort()

    assert warned == Enum.sort([due_soon.id, resolution_soon.id])
  end

  test "mix escalated.check_sla runs both checks" do
    assert Code.ensure_loaded?(Mix.Tasks.Escalated.CheckSla)
    assert function_exported?(Mix.Tasks.Escalated.CheckSla, :run, 1)
  end
end
