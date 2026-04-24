defmodule Mix.Tasks.Escalated.RunDueDelayedActions do
  @moduledoc """
  Mix task to sweep every `delayed_actions` row whose `execute_at` has
  elapsed and re-dispatch its `action_data` via `WorkflowExecutor`.

  Intended to be run periodically via a cron job or scheduler on the
  host app (the Phoenix plugin has no built-in scheduler — host apps
  decide the cadence, typically every minute).

  ## Usage

      mix escalated.run_due_delayed_actions
  """
  use Mix.Task

  @shortdoc "Runs every pending delayed workflow action whose wait has elapsed"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {processed, failed} = Escalated.Services.WorkflowExecutor.run_due_delayed_actions()

    Mix.shell().info(
      "Escalated: ran #{processed} delayed action(s). Errors: #{failed}."
    )
  end
end
