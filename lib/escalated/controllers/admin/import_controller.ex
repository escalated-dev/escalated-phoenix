defmodule Escalated.Controllers.Admin.ImportController do
  @moduledoc """
  The admin Import wizard, as escalated-laravel's `Admin\\ImportController`, on
  its paths and with its props:

    * Index    `GET  /admin/import` - adapters, recent jobs
    * Connect  `GET  /admin/import/:platform/connect`, with
      `POST /admin/import/:platform/test-connection` answering `{success[, error]}`
    * Mapping  `GET  /admin/import/:platform/mapping` - defaults and source fields
    * Review   `POST /admin/import/:platform/review` - echo of the choices; writes nothing
    * `POST /admin/import/:platform/start` - creates the job and queues the run
    * Progress `GET  /admin/import/progress/:job_id`, polled through
      `GET /admin/import/status/:job_id`, with
      `POST /admin/import/{pause,resume,cancel}/:job_id`

  Sources are the `Escalated.ImportAdapter` modules on the `"import.adapters"`
  filter; core ships none. Tested credentials wait in the session, sealed,
  until the import starts, and are never sent to the browser.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Import.{Credentials, Runner}
  alias Escalated.ImportAdapter
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.ImportJob

  def index(conn, _params) do
    jobs = repo().all(from(j in ImportJob, order_by: [desc: j.inserted_at], limit: 20))

    UIRenderer.render_page(conn, "Escalated/Admin/Import/Index", %{
      adapters:
        Enum.map(ImportAdapter.all(), fn adapter ->
          %{
            name: adapter.name(),
            display_name: adapter.display_name(),
            credential_fields: adapter.credential_fields()
          }
        end),
      jobs: Enum.map(jobs, &job_json/1)
    })
  end

  def connect(conn, %{"platform" => platform}) do
    with_adapter(conn, platform, fn adapter ->
      UIRenderer.render_page(conn, "Escalated/Admin/Import/Connect", %{
        platform: adapter.name(),
        display_name: adapter.display_name(),
        credential_fields: adapter.credential_fields()
      })
    end)
  end

  def test_connection(conn, %{"platform" => platform} = params) do
    with_adapter(conn, platform, fn adapter ->
      credentials =
        case params["credentials"] do
          %{} = posted -> Map.new(posted, fn {k, v} -> {to_string(k), scalar(v)} end)
          _ -> %{}
        end

      try do
        success = adapter.test_connection(credentials) == true

        conn =
          if success,
            do: put_session(conn, session_key(adapter), Credentials.seal(credentials)),
            else: conn

        json(conn, %{success: success})
      rescue
        error ->
          conn |> put_status(422) |> json(%{success: false, error: Exception.message(error)})
      end
    end)
  end

  def mapping(conn, %{"platform" => platform}) do
    with_adapter(conn, platform, fn adapter ->
      case stored_credentials(conn, adapter) do
        nil ->
          to_connect(conn, adapter)

        credentials ->
          entity_types = adapter.entity_types()

          UIRenderer.render_page(conn, "Escalated/Admin/Import/Mapping", %{
            platform: adapter.name(),
            display_name: adapter.display_name(),
            entity_types: entity_types,
            mappings:
              Map.new(entity_types, fn type ->
                {type,
                 %{
                   defaults: adapter.default_field_mappings(type),
                   source_fields: adapter.available_source_fields(type, credentials)
                 }}
              end)
          })
      end
    end)
  end

  def review(conn, %{"platform" => platform} = params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Import/Review", %{
      platform: platform,
      field_mappings: map_param(params["field_mappings"]),
      entity_types: params["entity_types"] |> List.wrap() |> Enum.map(&to_string/1)
    })
  end

  def start(conn, %{"platform" => platform} = params) do
    with_adapter(conn, platform, fn adapter ->
      case stored_credentials(conn, adapter) do
        nil ->
          to_connect(conn, adapter)

        credentials ->
          user = conn.assigns[:current_user]

          job =
            %ImportJob{}
            |> ImportJob.changeset(%{
              user_id: user && Map.get(user, :id),
              platform: adapter.name(),
              status: "mapping",
              credentials: Credentials.seal(credentials),
              field_mappings: map_param(params["field_mappings"])
            })
            |> repo().insert!()

          # The job holds them now, sealed.
          conn = delete_session(conn, session_key(adapter))
          :ok = Runner.dispatch(job)

          to_progress(conn, job)
      end
    end)
  end

  def progress(conn, %{"job_id" => id}) do
    with_job(conn, id, fn job ->
      UIRenderer.render_page(conn, "Escalated/Admin/Import/Progress", %{job: job_json(job)})
    end)
  end

  def status(conn, %{"job_id" => id}) do
    with_job(conn, id, fn job ->
      json(conn, %{
        status: job.status,
        progress: job.progress || %{},
        error_log: Enum.take(job.error_log || [], -50),
        started_at: job.started_at,
        completed_at: job.completed_at
      })
    end)
  end

  def pause(conn, %{"job_id" => id}) do
    with_job(conn, id, fn job ->
      if job.status == "importing",
        do: job |> ImportJob.changeset(%{status: "paused"}) |> repo().update!()

      conn |> put_flash(:info, "Import paused.") |> to_progress(job)
    end)
  end

  def resume(conn, %{"job_id" => id}) do
    with_job(conn, id, fn job ->
      if ImportJob.resumable?(job) do
        job =
          if job.status == "failed",
            do: job |> ImportJob.changeset(%{status: "mapping"}) |> repo().update!(),
            else: job

        :ok = Runner.dispatch(job)
      end

      conn |> put_flash(:info, "Import resumed.") |> to_progress(job)
    end)
  end

  def cancel(conn, %{"job_id" => id}) do
    with_job(conn, id, fn job ->
      job
      |> ImportJob.changeset(%{
        status: "failed",
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        credentials: nil
      })
      |> repo().update!()

      conn |> put_flash(:info, "Import cancelled.") |> to_progress(job)
    end)
  end

  @doc """
  The job as the screens read it, as Laravel's `ImportJob::toPageProps()`.
  Built from an explicit field list, so a column added later is not sent to
  the browser by default; the credentials never are. The error log is its
  last 50 entries, as the status poll sends.
  """
  def job_json(%ImportJob{} = job) do
    %{
      id: job.id,
      platform: job.platform,
      status: job.status,
      progress: job.progress || %{},
      field_mappings: job.field_mappings || %{},
      error_log: Enum.take(job.error_log || [], -50),
      started_at: job.started_at,
      completed_at: job.completed_at,
      created_at: job.inserted_at
    }
  end

  defp with_adapter(conn, platform, fun) do
    case ImportAdapter.find(platform) do
      nil -> conn |> put_status(404) |> json(%{error: "Import adapter not found: #{platform}"})
      adapter -> fun.(adapter)
    end
  end

  defp with_job(conn, id, fun) do
    case repo().get(ImportJob, id) do
      nil -> conn |> put_status(404) |> json(%{error: "Import job not found."})
      job -> fun.(job)
    end
  end

  defp session_key(adapter), do: "escalated.import.#{adapter.name()}.credentials"

  defp stored_credentials(conn, adapter),
    do: conn |> get_session(session_key(adapter)) |> Credentials.open()

  defp to_connect(conn, adapter) do
    conn
    |> put_flash(:error, "Credentials expired. Please reconnect.")
    |> redirect(to: "#{base_path()}/#{adapter.name()}/connect")
  end

  defp to_progress(conn, job), do: redirect(conn, to: "#{base_path()}/progress/#{job.id}")

  defp map_param(%{} = value), do: value
  defp map_param(_), do: %{}

  defp scalar(value) when is_binary(value), do: value
  defp scalar(nil), do: ""
  defp scalar(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp scalar(_), do: ""

  defp base_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/import"

  defp repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())
end
