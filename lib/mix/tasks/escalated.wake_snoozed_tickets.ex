defmodule Mix.Tasks.Escalated.WakeSnoozedTickets do
  @moduledoc """
  Mix task to wake all snoozed tickets whose snooze period has elapsed.

  Intended to be run periodically via a cron job or scheduler.

  ## Usage

      mix escalated.wake_snoozed_tickets
  """
  use Mix.Task

  @shortdoc "Wakes snoozed tickets that are past their snooze-until time"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    results = Escalated.Services.TicketService.wake_snoozed_tickets()

    woken = Enum.count(results, fn
      {:ok, _} -> true
      _ -> false
    end)

    errors = Enum.count(results, fn
      {:error, _} -> true
      _ -> false
    end)

    Mix.shell().info("Escalated: Woke #{woken} snoozed ticket(s). Errors: #{errors}.")
  end
end
