defmodule Mix.Tasks.Escalated.EvaluateEscalations do
  @shortdoc "Evaluate escalation rules against open tickets"
  @moduledoc false
  use Mix.Task

  alias Escalated.Services.EscalationService

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    count = EscalationService.evaluate_rules(Escalated.repo())
    Mix.shell().info("Escalated: escalation evaluation complete — #{count} ticket(s) affected.")
  end
end
