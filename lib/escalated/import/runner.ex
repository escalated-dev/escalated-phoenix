defmodule Escalated.Import.Runner do
  @moduledoc """
  Runs an import outside the request that started it, as escalated-laravel
  queues `ImportService::run`.

  By default the run is a task under `Escalated.ImportTaskSupervisor`, carrying
  the request's tenant. A host with a job queue (Oban, say) takes it over with

      config :escalated, import_dispatcher: &MyApp.Jobs.enqueue_import/1

  which receives the job id, and calls `run/1` from its worker.

  A run that raises marks the job failed; resuming it continues from its saved
  cursors.
  """
  require Logger

  alias Escalated.Schemas.ImportJob
  alias Escalated.Services.ImportService

  @supervisor Escalated.ImportTaskSupervisor

  @doc "Queues the job to run in the background."
  def dispatch(%ImportJob{id: id}) do
    case Escalated.config(:import_dispatcher) do
      fun when is_function(fun, 1) ->
        fun.(id)
        :ok

      _ ->
        {:ok, _pid} =
          Task.Supervisor.start_child(@supervisor, Escalated.Tenancy.capture(fn -> run(id) end))

        :ok
    end
  end

  @doc "Runs (or resumes) the import job with this id."
  def run(id) do
    repo = Escalated.Tenancy.scoped_repo(Escalated.repo())

    case repo.get(ImportJob, id) do
      nil ->
        :ok

      %ImportJob{status: "completed"} ->
        :ok

      job ->
        try do
          ImportService.run(job)
          :ok
        rescue
          error ->
            Logger.error("Escalated import #{id} failed: #{Exception.message(error)}")
            job |> ImportJob.changeset(%{status: "failed"}) |> repo.update()
            :error
        end
    end
  end

  @doc "Waits for every in-process run started so far (tests, graceful shutdown)."
  def await_all(timeout \\ 15_000) do
    @supervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      after
        timeout -> :timeout
      end
    end)
  end
end
