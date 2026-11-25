defmodule Mix.Tasks.Escalated.CheckSla do
  @moduledoc """
  Marks SLA breaches and sends SLA warnings.

  Runs `Escalated.Services.SlaService.check_breaches/0`, which flags tickets
  past a deadline and dispatches `sla.breached`, then
  `Escalated.Services.SlaService.check_warnings/1`, which dispatches
  `sla.warning` for deadlines inside the warning window. Schedule it every
  minute like the other Escalated tasks (see `Escalated.Scheduler`); a warning
  repeats on every run while its deadline stays inside the window.

  Each run records the scheduler heartbeat the admin pages read: when it is
  missing or more than 15 minutes old they warn that the recurring jobs are
  not running.

  ## Usage

      mix escalated.check_sla                    # warn 30 minutes ahead
      mix escalated.check_sla --warn-minutes 60
  """
  use Mix.Task


  @shortdoc "Marks SLA breaches and sends SLA warnings"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Escalated.Tenancy.Maintenance.run(args, &run_for_tenant/1)
  end

  defp run_for_tenant(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [warn_minutes: :integer])

    {breached, warned} = Escalated.Scheduler.check_sla(Keyword.get(opts, :warn_minutes, 30))

    Mix.shell().info(
      "Escalated: #{length(breached)} SLA breach(es), #{length(warned)} warning(s)."
    )
  end
end
