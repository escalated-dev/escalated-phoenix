defmodule Mix.Tasks.Escalated.EvaluateEscalations do
  @shortdoc "Evaluate escalation rules against open tickets"
  @moduledoc false
  use Mix.Task

  alias Escalated.Services.EscalationService

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Escalated.Tenancy.Maintenance.run(args, &run_for_tenant/1)
  end

  defp run_for_tenant(_args) do
    count = EscalationService.evaluate_rules(Escalated.repo())
    Mix.shell().info("Escalated: escalation evaluation complete — #{count} ticket(s) affected.")
  end
end
