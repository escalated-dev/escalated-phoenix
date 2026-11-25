defmodule Escalated.Scheduler do
  @moduledoc """
  Escalated's recurring jobs, an opt-in in-process runner for them, and the
  heartbeat that tells admins whether they run.

  SLA breach checks, escalation rules, automations, delayed workflow actions
  and snooze wake-ups only happen when something runs them on a timer:

  | Job                       | Mix task                               | Interval        |
  |---------------------------|----------------------------------------|-----------------|
  | `:check_sla`              | `mix escalated.check_sla`              | every minute    |
  | `:run_due_delayed_actions`| `mix escalated.run_due_delayed_actions`| every minute    |
  | `:wake_snoozed_tickets`   | `mix escalated.wake_snoozed_tickets`   | every minute    |
  | `:evaluate_escalations`   | `mix escalated.evaluate_escalations`   | every 5 minutes |
  | `:run_automations`        | `mix escalated.run_automations`        | every 5 minutes |

  ## Running them in-process (opt-in)

  Add the scheduler to your application's supervision tree, after your repo:

      children = [
        MyApp.Repo,
        Escalated.Scheduler,
        MyAppWeb.Endpoint
      ]

  It runs each job at its interval, one run of a job at a time, through
  `Escalated.Tenancy.Maintenance` (so every tenant in the trusted catalog when
  tenancy is on). A job that raises is logged and runs again at its next tick.
  On a cluster, start it on one node only (or schedule `run/1` with Oban or
  Quantum instead), or every node runs every job.

  Options: `:jobs` (the job names to run, default all of `jobs/0`),
  `:intervals` (a map of job name to milliseconds, overriding the defaults),
  `:name` (default `Escalated.Scheduler`).

  ## Running them yourself

  Without the scheduler, run each job at its interval from your own scheduler:
  `Escalated.Scheduler.run(:check_sla)` from Oban or Quantum (also in a
  release, where Mix tasks are not available), or the Mix task from cron.

  ## Heartbeat

  Every SLA check run records a heartbeat in the settings table. `status/1`
  reports the jobs as not running when it is missing or more than 15 minutes
  old; the admin Settings and Reports pages receive it as their `scheduler`
  prop and `mix escalated.doctor` prints it.
  """
  use GenServer

  require Logger

  alias Escalated.Services.{
    AutomationRunner,
    EscalationService,
    SettingsService,
    SlaService,
    TicketService,
    WorkflowExecutor
  }

  @heartbeat_key "scheduler_sla_heartbeat_at"
  @heartbeat_group "scheduler"
  @stale_after_seconds 15 * 60
  @minute 60_000

  # {name, mix task, interval as shown, interval in ms}
  @jobs [
    {:check_sla, "mix escalated.check_sla", "every minute", @minute},
    {:run_due_delayed_actions, "mix escalated.run_due_delayed_actions", "every minute", @minute},
    {:wake_snoozed_tickets, "mix escalated.wake_snoozed_tickets", "every minute", @minute},
    {:evaluate_escalations, "mix escalated.evaluate_escalations", "every 5 minutes", 5 * @minute},
    {:run_automations, "mix escalated.run_automations", "every 5 minutes", 5 * @minute}
  ]

  @job_names Enum.map(@jobs, &elem(&1, 0))

  @doc "The recurring job names, in the order the table above lists them."
  def jobs, do: @job_names

  @doc "What to schedule: each job's Mix task and interval, as `%{command, interval}`."
  def commands do
    Enum.map(@jobs, fn {_name, command, interval, _ms} ->
      %{command: command, interval: interval}
    end)
  end

  @doc """
  Runs one job in the current process for every tenant (see
  `Escalated.Tenancy.Maintenance`) and returns its per-tenant results.
  """
  def run(name) when name in @job_names do
    Escalated.Tenancy.Maintenance.run([], fn _args -> run_once(name) end)
  end

  @doc """
  Runs one job once in the current context (no tenant sweep). The Mix tasks
  call this per tenant.
  """
  def run_once(:check_sla), do: check_sla(30)
  def run_once(:run_due_delayed_actions), do: WorkflowExecutor.run_due_delayed_actions()
  def run_once(:wake_snoozed_tickets), do: TicketService.wake_snoozed_tickets()
  def run_once(:evaluate_escalations), do: EscalationService.evaluate_rules(Escalated.repo())
  def run_once(:run_automations), do: AutomationRunner.run(Escalated.repo())

  @doc """
  Marks SLA breaches, sends SLA warnings `warn_minutes` ahead, and records the
  heartbeat. Returns `{breached, warned}`.
  """
  def check_sla(warn_minutes) do
    breached = SlaService.check_breaches()
    warned = SlaService.check_warnings(warn_minutes)
    record_heartbeat()
    {breached, warned}
  end

  # ---------------------------------------------------------------------------
  # Heartbeat
  # ---------------------------------------------------------------------------

  @doc "Records that the SLA check ran at `at` (default now)."
  def record_heartbeat(at \\ DateTime.utc_now()) do
    value = at |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    {:ok, _} = SettingsService.set(@heartbeat_key, value, @heartbeat_group)
    :ok
  end

  @doc "When the SLA check last ran, or nil."
  def last_run_at do
    with value when is_binary(value) <- SettingsService.get(@heartbeat_key),
         {:ok, at, _offset} <- DateTime.from_iso8601(value) do
      at
    else
      _ -> nil
    end
  end

  @doc """
  Whether the recurring jobs are running, for admins:

      %{healthy: boolean, last_run_at: iso8601 | nil, message: string,
        commands: [%{command: string, interval: string}]}

  `healthy` is false when the heartbeat is missing or more than 15 minutes
  older than `now`.
  """
  def status(now \\ DateTime.utc_now()) do
    last = last_run_at()
    healthy = not is_nil(last) and DateTime.diff(now, last, :second) <= @stale_after_seconds

    %{
      healthy: healthy,
      last_run_at: last && DateTime.to_iso8601(last),
      message: message(healthy, last),
      commands: commands()
    }
  end

  defp message(true, _last), do: "Escalated's recurring jobs are running."

  defp message(false, nil) do
    "Escalated's recurring jobs are not running: the SLA check has never run, so SLA " <>
      "breaches, escalation rules, automations and snooze wake-ups are not processed. " <>
      "Add Escalated.Scheduler to your supervision tree, or schedule each job below."
  end

  defp message(false, _last) do
    "Escalated's recurring jobs are not running: the SLA check has not run for more " <>
      "than 15 minutes, so SLA breaches, escalation rules, automations and snooze " <>
      "wake-ups are not processed. Add Escalated.Scheduler to your supervision tree, " <>
      "or schedule each job below."
  end

  # ---------------------------------------------------------------------------
  # In-process runner
  # ---------------------------------------------------------------------------

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(opts) do
    names = Keyword.get(opts, :jobs, @job_names)

    unknown = names -- @job_names

    if unknown != [] do
      raise ArgumentError, "unknown Escalated.Scheduler jobs: #{inspect(unknown)}"
    end

    overrides = Map.new(Keyword.get(opts, :intervals, %{}))

    intervals =
      for {name, _command, _interval, ms} <- @jobs, name in names, into: %{} do
        {name, Map.get(overrides, name, ms)}
      end

    # The first run waits one interval, so the host's repo has started.
    Enum.each(intervals, fn {name, ms} -> Process.send_after(self(), {:run, name}, ms) end)

    {:ok, %{intervals: intervals}}
  end

  @impl GenServer
  def handle_info({:run, name}, %{intervals: intervals} = state) do
    try do
      run(name)
    rescue
      error ->
        Logger.error("Escalated.Scheduler: #{name} failed: #{inspect(error.__struct__)}")
    catch
      kind, _reason ->
        Logger.error("Escalated.Scheduler: #{name} failed: #{kind}")
    end

    Process.send_after(self(), {:run, name}, Map.fetch!(intervals, name))
    {:noreply, state}
  end
end
