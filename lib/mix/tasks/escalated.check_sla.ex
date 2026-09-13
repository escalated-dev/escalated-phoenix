defmodule Mix.Tasks.Escalated.CheckSla do
  @moduledoc """
  Marks SLA breaches and sends SLA warnings.

  Runs `Escalated.Services.SlaService.check_breaches/0`, which flags tickets
  past a deadline and dispatches `sla.breached`, then
  `Escalated.Services.SlaService.check_warnings/1`, which dispatches
  `sla.warning` for deadlines inside the warning window. Schedule it like the
  other Escalated tasks; a warning repeats on every run while its deadline
  stays inside the window.

  ## Usage

      mix escalated.check_sla                    # warn 30 minutes ahead
      mix escalated.check_sla --warn-minutes 60
  """
  use Mix.Task

  alias Escalated.Services.SlaService

  @shortdoc "Marks SLA breaches and sends SLA warnings"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [warn_minutes: :integer])
    Mix.Task.run("app.start")

    breached = SlaService.check_breaches()
    warned = SlaService.check_warnings(Keyword.get(opts, :warn_minutes, 30))

    Mix.shell().info(
      "Escalated: #{length(breached)} SLA breach(es), #{length(warned)} warning(s)."
    )
  end
end
