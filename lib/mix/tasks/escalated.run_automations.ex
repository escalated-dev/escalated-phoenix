defmodule Mix.Tasks.Escalated.RunAutomations do
  @moduledoc """
  Runs the time-based admin automations (`Escalated.Services.AutomationRunner`)
  against open tickets. Schedule it every five minutes (see
  `Escalated.Scheduler`).

  ## Usage

      mix escalated.run_automations
      mix escalated.run_automations --tenant ID
  """
  use Mix.Task

  @shortdoc "Runs the time-based automations against open tickets"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Escalated.Tenancy.Maintenance.run(args, &run_for_tenant/1)
  end

  defp run_for_tenant(_args) do
    count = Escalated.Scheduler.run_once(:run_automations)
    Mix.shell().info("Escalated: automations applied #{count} action(s).")
  end
end
