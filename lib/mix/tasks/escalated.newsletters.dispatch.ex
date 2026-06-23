defmodule Mix.Tasks.Escalated.Newsletters.Dispatch do
  @shortdoc "Plan due scheduled newsletters and dispatch a delivery batch"
  @moduledoc false
  use Mix.Task

  import Ecto.Query
  alias Escalated.Schemas.Newsletter.Newsletter
  alias Escalated.Services.Newsletter.{Dispatcher, Planner}

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    if newsletters_enabled?() do
      plan_due_scheduled()
      Dispatcher.dispatch_batch()
      Mix.shell().info("Escalated: newsletter dispatch tick complete.")
    else
      Mix.shell().info("Newsletter feature disabled — skipping.")
      :ok
    end
  end

  defp newsletters_enabled? do
    Application.get_env(:escalated, :enable_newsletters, false) in [true, "true", 1, "1"]
  end

  defp plan_due_scheduled do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    repo = Escalated.repo()

    due =
      from(n in Newsletter,
        where: n.status == "scheduled" and not is_nil(n.scheduled_at) and n.scheduled_at <= ^now
      )
      |> repo.all()

    Enum.each(due, &Planner.plan/1)
  end
end
