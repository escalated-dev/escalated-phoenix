defmodule Mix.Tasks.Escalated.Doctor do
  @moduledoc """
  Checks an install's setup and reports what is missing:

    * the user schema and staff gates (`Escalated.UserContract`): an unset or
      non-Ecto `user_schema`, a schema without `:id`, and no `agent_check` /
      `admin_check` and no `is_agent` / `is_admin` fields;
    * the recurring jobs (`Escalated.Scheduler`): whether the SLA check's
      heartbeat is recent, and what to schedule when it is not.

  Exits non-zero when there is an error (warnings alone do not fail it).

  ## Usage

      mix escalated.doctor
      mix escalated.doctor --tenant ID

  In a release, where Mix is not available, call
  `Escalated.UserContract.problems/0` and `Escalated.Scheduler.status/0`.
  """
  use Mix.Task

  @shortdoc "Checks the user schema, staff gates and recurring jobs"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    problems = Escalated.UserContract.problems() ++ scheduler_problems(args)

    Enum.each(problems, fn {level, message} ->
      Mix.shell().info("[#{level}] #{message}")
    end)

    if problems == [], do: Mix.shell().info("Escalated: no setup problems found.")

    if Enum.any?(problems, &(elem(&1, 0) == :error)) do
      Mix.raise("Escalated: setup problems found (see above).")
    end
  end

  defp scheduler_problems(args) do
    args
    |> Escalated.Tenancy.Maintenance.run(fn _args -> Escalated.Scheduler.status() end)
    |> Enum.flat_map(fn {tenant, status} -> scheduler_problem(tenant, status) end)
  rescue
    error ->
      [{:error, "could not read the scheduler heartbeat: #{Exception.message(error)}"}]
  end

  defp scheduler_problem(_tenant, %{healthy: true}), do: []

  defp scheduler_problem(tenant, status) do
    where = if tenant == "", do: "", else: " (tenant #{tenant})"

    commands =
      Enum.map_join(status.commands, "\n", &"    #{&1.command}  #{&1.interval}")

    [{:warning, "#{status.message}#{where}\n#{commands}"}]
  end
end
