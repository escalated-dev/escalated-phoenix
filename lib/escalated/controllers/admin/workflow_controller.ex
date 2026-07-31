defmodule Escalated.Controllers.Admin.WorkflowController do
  @moduledoc """
  Admin CRUD over event-driven Workflow rows.

  Workflows fire automatically the moment a matching ticket lifecycle
  event occurs (`ticket.created`, `reply.created`, `ticket.status_changed`,
  ...). The runner is invoked inline from
  `Escalated.Services.TicketService` — there is no auto-emitting event bus.

  Distinct from the Automation controller (time-based cron) and the Macro
  controller (agent manual one-click). See escalated-developer-context/
  domain-model/workflows-automations-macros.md.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.Workflow

  def index(conn, _params) do
    repo = Escalated.repo()

    workflows =
      Workflow
      |> order_by([w], asc: w.position, asc: w.id)
      |> repo.all()

    UIRenderer.render_page(conn, "Escalated/Admin/Workflows/Index", %{
      workflows: Enum.map(workflows, &Workflow.to_json/1),
      trigger_events: available_trigger_events()
    })
  end

  def show(conn, %{"id" => id}) do
    case Escalated.repo().get(Workflow, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Workflow not found"})

      workflow ->
        UIRenderer.render_page(conn, "Escalated/Admin/Workflows/Show", %{
          workflow: Workflow.to_json(workflow),
          trigger_events: available_trigger_events()
        })
    end
  end

  def create(conn, %{"workflow" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    repo = Escalated.repo()
    params = params |> normalize_params() |> put_next_position(repo)

    %Workflow{}
    |> Workflow.changeset(params)
    |> repo.insert()
    |> case do
      {:ok, _workflow} ->
        conn |> put_flash(:info, "Workflow created.") |> redirect(to: admin_workflows_path(conn))

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "workflow" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case repo.get(Workflow, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Workflow not found"})

      workflow ->
        workflow
        |> Workflow.changeset(normalize_params(params))
        |> repo.update()
        |> case do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Workflow updated.")
            |> redirect(to: admin_workflows_path(conn))

          {:error, cs} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Workflow, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Workflow not found"})

      workflow ->
        repo.delete(workflow)
        conn |> put_flash(:info, "Workflow deleted.") |> redirect(to: admin_workflows_path(conn))
    end
  end

  # The shared frontend builder posts the trigger under the `trigger` key
  # (aliased to `trigger_event` on read via Workflow.to_json/1). Accept
  # either so both the Vue builder and direct API callers work.
  defp normalize_params(params) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)

    case {Map.get(params, "trigger_event"), Map.get(params, "trigger")} do
      {nil, trigger} when not is_nil(trigger) -> Map.put(params, "trigger_event", trigger)
      _ -> params
    end
  end

  # Append new workflows to the end of the ordered list (mirrors the Laravel
  # reference: max(position) + 1) unless the caller pinned a position.
  defp put_next_position(params, repo) do
    if Map.has_key?(params, "position") do
      params
    else
      max = repo.one(from(w in Workflow, select: max(w.position))) || 0
      Map.put(params, "position", max + 1)
    end
  end

  # The 5 canonical event triggers (developer-context: Workflows fire on
  # exactly these). Surfaced to the builder as select options.
  defp available_trigger_events do
    [
      %{value: "ticket.created", label: "Ticket Created"},
      %{value: "ticket.updated", label: "Ticket Updated"},
      %{value: "ticket.assigned", label: "Ticket Assigned"},
      %{value: "ticket.status_changed", label: "Ticket Status Changed"},
      %{value: "reply.created", label: "Reply Created"}
    ]
  end

  defp admin_workflows_path(_conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/workflows"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
