defmodule Escalated.SchedulerTest do
  @moduledoc """
  The recurring jobs only run when something schedules them. The SLA check
  records a heartbeat; admins are warned (the `scheduler` prop on the admin
  Settings and Reports pages) when it is missing or more than 15 minutes old,
  with what to schedule. `Escalated.Scheduler` runs the jobs in-process when
  the host adds it to its supervision tree.
  """
  use Escalated.PageCase

  alias Escalated.Scheduler

  @commands [
    "mix escalated.check_sla",
    "mix escalated.run_due_delayed_actions",
    "mix escalated.wake_snoozed_tickets",
    "mix escalated.evaluate_escalations",
    "mix escalated.run_automations"
  ]

  setup do
    previous = Application.fetch_env(:escalated, :admin_check)
    Application.put_env(:escalated, :admin_check, &(&1[:is_admin] == true))

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :admin_check, value)
        :error -> Application.delete_env(:escalated, :admin_check)
      end
    end)

    %{admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})}
  end

  describe "heartbeat" do
    test "with no heartbeat the jobs are reported as not running" do
      status = Scheduler.status()

      refute status.healthy
      assert status.last_run_at == nil
      assert status.message =~ "not running"
      assert status.message =~ "Escalated.Scheduler"
      assert Enum.map(status.commands, & &1.command) == @commands
      assert Enum.all?(status.commands, &(&1.interval =~ "every"))
    end

    test "the SLA check records the heartbeat, and the jobs then count as running" do
      assert {_breached, _warned} = Scheduler.check_sla(30)

      status = Scheduler.status()
      assert status.healthy
      assert {:ok, _at, 0} = DateTime.from_iso8601(status.last_run_at)
      assert status.message =~ "running"
    end

    test "a heartbeat more than 15 minutes old is stale" do
      ran_at = ~U[2026-11-24 10:00:00Z]
      Scheduler.record_heartbeat(ran_at)

      assert Scheduler.status(DateTime.add(ran_at, 15 * 60, :second)).healthy

      stale = Scheduler.status(DateTime.add(ran_at, 15 * 60 + 1, :second))
      refute stale.healthy
      assert stale.last_run_at == "2026-11-24T10:00:00Z"
      assert stale.message =~ "more than 15 minutes"
    end

    test "mix escalated.check_sla records the heartbeat" do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      Mix.Tasks.Escalated.CheckSla.run([])

      assert_received {:mix_shell, :info, ["Escalated: " <> _]}
      assert Scheduler.status().healthy
    end
  end

  describe "admin warning" do
    test "the Settings page carries the scheduler status", %{admin: admin} do
      props = visit(:get, "/support/admin/settings", admin) |> page!("Escalated/Admin/Settings")

      assert %{"healthy" => false, "last_run_at" => nil, "message" => message} =
               props["scheduler"]

      assert message =~ "not running"
      assert Enum.map(props["scheduler"]["commands"], & &1["command"]) == @commands

      Scheduler.record_heartbeat()
      props = visit(:get, "/support/admin/settings", admin) |> page!("Escalated/Admin/Settings")
      assert props["scheduler"]["healthy"] == true
    end

    test "the Reports overview and dashboard carry it too", %{admin: admin} do
      for {path, component} <- [
            {"/support/admin/reports", "Escalated/Admin/Reports"},
            {"/support/admin/reports/dashboard", "Escalated/Admin/Reports/Dashboard"}
          ] do
        props = visit(:get, path, admin) |> page!(component)
        assert props["scheduler"]["healthy"] == false, path
      end
    end
  end

  describe "in-process runner" do
    test "runs each job at its interval and records the heartbeat" do
      start_supervised!(
        {Scheduler,
         name: :escalated_scheduler_test, jobs: [:check_sla], intervals: %{check_sla: 10}}
      )

      assert eventually(fn -> Scheduler.status().healthy end)
    end

    test "a job that raises is logged and scheduled again" do
      # Tenancy on with no tenant catalog: the sweep raises before any work.
      Application.put_env(:escalated, :tenancy_enabled, true)
      on_exit(fn -> Application.delete_env(:escalated, :tenancy_enabled) end)

      state = %{intervals: %{check_sla: 0}}

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:noreply, ^state} = Scheduler.handle_info({:run, :check_sla}, state)
        end)

      assert log =~ "Escalated.Scheduler: check_sla failed"
      assert_receive {:run, :check_sla}
    end

    test "an unknown job name is refused" do
      assert_raise ArgumentError, ~r/unknown Escalated.Scheduler jobs/, fn ->
        Scheduler.init(jobs: [:nope])
      end
    end
  end

  defp eventually(fun, tries \\ 100) do
    cond do
      fun.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(fun, tries - 1)
    end
  end
end
