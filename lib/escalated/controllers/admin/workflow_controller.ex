defmodule Escalated.Controllers.Admin.WorkflowController do
  @moduledoc """
  Admin CRUD over event-driven Workflow rows.

  Workflows fire automatically the moment a matching ticket lifecycle
  event occurs: every event `Escalated.Events.emit/2` announces, under the
  canonical names of decisions/2026-10-21-event-vocabulary.md. There is no
  auto-emitting event bus; the services call `emit/2` inline.

  What goes over the wire (page props, the create/update body, toggle and
  reorder) is fixed by escalated-developer-context/domain-model/
  workflow-admin-contract.md. Where this module and that doc disagree, the
  doc wins.

  Distinct from the Automation controller (time-based cron) and the Macro
  controller (agent manual one-click). See escalated-developer-context/
  domain-model/workflows-automations-macros.md.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{Ticket, Workflow, WorkflowLog}
  alias Escalated.Services.WorkflowEngine

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

  def new(conn, _params), do: render_form(conn, nil)

  def edit(conn, %{"id" => id}) do
    case Escalated.repo().get(Workflow, id) do
      nil -> not_found(conn)
      workflow -> render_form(conn, Workflow.to_json(workflow))
    end
  end

  def show(conn, %{"id" => _} = params), do: edit(conn, params)

  @logs_limit 200

  @doc """
  The run log, newest first, optionally for one workflow (`?workflow=id`):
  `Escalated/Admin/Workflows/Logs` with the shape escalated-laravel's
  `WorkflowController::logs` sends.
  """
  def logs(conn, params) do
    repo = Escalated.repo()

    query =
      from(l in WorkflowLog, order_by: [desc: l.inserted_at, desc: l.id], limit: @logs_limit)

    query =
      case Integer.parse(to_string(params["workflow"] || "")) do
        {id, ""} -> where(query, [l], l.workflow_id == ^id)
        _ -> query
      end

    logs = repo.all(query)
    workflows = repo.all(from(w in Workflow, order_by: [asc: w.position, asc: w.id]))
    names = Map.new(workflows, &{&1.id, &1.name})

    references =
      case logs |> Enum.map(& &1.ticket_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
        [] ->
          %{}

        ids ->
          from(t in Ticket, where: t.id in ^ids, select: {t.id, t.reference})
          |> repo.all()
          |> Map.new()
      end

    UIRenderer.render_page(conn, "Escalated/Admin/Workflows/Logs", %{
      logs: Enum.map(logs, &log_json(&1, names, references)),
      workflows: Enum.map(workflows, &%{id: &1.id, name: &1.name})
    })
  end

  @doc "A workflow's own log link: the log page filtered to it."
  def workflow_logs(conn, %{"id" => id}) do
    prefix = Escalated.config(:route_prefix, "/support")
    redirect(conn, to: "#{prefix}/admin/workflows/logs?" <> URI.encode_query(%{workflow: id}))
  end

  defp log_json(log, names, references) do
    details = log.actions_executed || []

    %{
      id: log.id,
      workflow_id: log.workflow_id,
      workflow_name: Map.get(names, log.workflow_id),
      ticket_id: log.ticket_id,
      ticket_reference: Map.get(references, log.ticket_id),
      event: log.trigger_event,
      trigger_event: log.trigger_event,
      matched: log.conditions_matched,
      status: log.status,
      error: log.error_message,
      duration_ms:
        log.started_at && log.completed_at &&
          DateTime.diff(log.completed_at, log.started_at, :millisecond),
      # The page's "Actions" column is a count; the actions go out as details.
      actions_executed: length(details),
      action_details:
        Enum.map(details, fn detail ->
          %{
            action_type: detail["type"],
            status: detail["status"],
            error: detail["reason"],
            message: detail["reason"]
          }
        end),
      created_at: log.inserted_at && DateTime.to_iso8601(log.inserted_at)
    }
  end

  # The same Form page serves create and edit; `workflow` is nil on create.
  defp render_form(conn, workflow) do
    UIRenderer.render_page(conn, "Escalated/Admin/Workflows/Form", %{
      workflow: workflow,
      trigger_events: available_trigger_events(),
      action_types: available_action_types(),
      operators: WorkflowEngine.operators()
    })
  end

  def create(conn, %{"workflow" => params}) when is_map(params), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    repo = Escalated.repo()
    params = params |> normalize_params() |> put_next_position(repo)

    %Workflow{}
    |> Workflow.form_changeset(params)
    |> repo.insert()
    |> case do
      {:ok, _workflow} ->
        conn |> put_flash(:info, "Workflow created.") |> redirect(to: admin_workflows_path())

      {:error, changeset} ->
        invalid(conn, changeset, "#{admin_workflows_path()}/new")
    end
  end

  def update(conn, %{"id" => id, "workflow" => params}) when is_map(params),
    do: do_update(conn, id, params)

  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case repo.get(Workflow, id) do
      nil ->
        not_found(conn)

      workflow ->
        workflow
        |> Workflow.form_changeset(normalize_params(params))
        |> repo.update()
        |> case do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Workflow updated.")
            |> redirect(to: admin_workflows_path())

          {:error, changeset} ->
            invalid(conn, changeset, "#{admin_workflows_path()}/#{workflow.id}/edit")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Workflow, id) do
      nil ->
        not_found(conn)

      workflow ->
        repo.delete(workflow)
        conn |> put_flash(:info, "Workflow deleted.") |> redirect(to: admin_workflows_path())
    end
  end

  @doc "Flips `is_active` (the Index page's enable switch). Takes no body."
  def toggle(conn, %{"id" => id}) do
    repo = Escalated.repo()

    with %Workflow{} = workflow <- repo.get(Workflow, id),
         {:ok, updated} <-
           workflow |> Ecto.Changeset.change(is_active: !workflow.is_active) |> repo.update() do
      message = if updated.is_active, do: "Workflow enabled.", else: "Workflow disabled."
      conn |> put_flash(:info, message) |> redirect(to: admin_workflows_path())
    else
      nil -> not_found(conn)
      {:error, changeset} -> invalid(conn, changeset, admin_workflows_path())
    end
  end

  @doc """
  Stores the order the Index page was dragged into. `workflow_ids` lists every
  workflow in its new order; positions are rewritten from 1. Ids that name no
  workflow are ignored.
  """
  def reorder(conn, %{"workflow_ids" => ids}) when is_list(ids) do
    repo = Escalated.repo()

    positions =
      ids
      |> Enum.map(&parse_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index(1)

    {:ok, _} =
      repo.transaction(fn ->
        Enum.each(positions, fn {id, position} ->
          repo.update_all(from(w in Workflow, where: w.id == ^id), set: [position: position])
        end)
      end)

    conn |> put_flash(:info, "Workflow order saved.") |> redirect(to: admin_workflows_path())
  end

  def reorder(conn, _params) do
    invalid(
      conn,
      %{"workflow_ids" => "must be a list of workflow ids"},
      admin_workflows_path()
    )
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp normalize_params(params) do
    params
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> alias_trigger()
    |> default_conditions()
  end

  # `trigger_event` is the contract's key. `trigger` is the builder's older
  # spelling, still accepted from callers that send it.
  defp alias_trigger(params) do
    case {Map.get(params, "trigger_event"), Map.get(params, "trigger")} do
      {nil, trigger} when not is_nil(trigger) -> Map.put(params, "trigger_event", trigger)
      _ -> params
    end
  end

  # Omitted conditions mean "match every ticket". They are stored in the
  # canonical shape rather than as an empty object, so the builder reads back
  # an `all` list instead of an object with neither key.
  defp default_conditions(params) do
    case Map.get(params, "conditions") do
      conditions when is_nil(conditions) or conditions == %{} ->
        Map.put(params, "conditions", %{"all" => []})

      _ ->
        params
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

  @trigger_labels %{
    "ticket.created" => "Ticket Created",
    "ticket.updated" => "Ticket Updated",
    "ticket.status_changed" => "Ticket Status Changed",
    "ticket.resolved" => "Ticket Resolved",
    "ticket.closed" => "Ticket Closed",
    "ticket.reopened" => "Ticket Reopened",
    "ticket.assigned" => "Ticket Assigned",
    "ticket.unassigned" => "Ticket Unassigned",
    "ticket.escalated" => "Ticket Escalated",
    "ticket.priority_changed" => "Ticket Priority Changed",
    "ticket.department_changed" => "Ticket Department Changed",
    "ticket.tag_added" => "Tag Added",
    "ticket.tag_removed" => "Tag Removed",
    "reply.created" => "Reply Created",
    "note.created" => "Internal Note Added",
    "sla.warning" => "SLA Warning",
    "sla.breached" => "SLA Breached"
  }

  # The events this package fires (Escalated.Events.emitted/0), each of which
  # runs the workflows saved against it. The builder offers exactly this list,
  # so naming an event nothing emits would let an admin save a workflow that
  # never runs.
  defp available_trigger_events do
    Enum.map(Escalated.Events.emitted(), fn event ->
      %{value: event, label: Map.get(@trigger_labels, event, event)}
    end)
  end

  # The actions WorkflowExecutor runs from a saved workflow: the core catalog
  # plus add_follower and delay. `send_webhook` has no executor clause.
  defp available_action_types do
    [
      %{value: "change_status", label: "Change Status"},
      %{value: "change_priority", label: "Change Priority"},
      %{value: "add_tag", label: "Add Tag"},
      %{value: "remove_tag", label: "Remove Tag"},
      %{value: "set_department", label: "Set Department"},
      %{value: "assign_agent", label: "Assign Agent"},
      %{value: "add_note", label: "Add Internal Note"},
      %{value: "insert_canned_reply", label: "Insert Canned Reply"},
      %{value: "add_follower", label: "Add Follower"},
      %{value: "delay", label: "Delay (minutes)"}
    ]
  end

  # A validation failure. An Inertia form visit cannot consume a JSON 422, so it
  # gets the Inertia convention: errors in the session, redirect back. Requests
  # without the X-Inertia header keep the JSON 422 they always had.
  defp invalid(conn, errors, fallback_path) do
    if get_req_header(conn, "x-inertia") == ["true"] do
      conn
      |> assign_inertia_errors(errors)
      |> redirect(to: back_path(conn, fallback_path))
    else
      conn |> put_status(422) |> Phoenix.Controller.json(%{errors: json_errors(errors)})
    end
  end

  # apply/3 rather than a direct call because `inertia` is an OPTIONAL
  # dependency; see Escalated.Rendering.UIRenderer.
  defp assign_inertia_errors(conn, errors) do
    if Code.ensure_loaded?(Inertia.Controller) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(Inertia.Controller, :assign_errors, [conn, errors])
    else
      conn
    end
  end

  # The page the form was submitted from. Browsers send an absolute Referer,
  # and redirect/2 only accepts a local path, so keep just the path and query.
  defp back_path(conn, fallback) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> rest = path, query: query} <- URI.parse(referer),
         false <- String.starts_with?(rest, "/") do
      if query, do: "#{path}?#{query}", else: path
    else
      _ -> fallback
    end
  end

  defp not_found(conn) do
    conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Workflow not found"})
  end

  defp admin_workflows_path do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/workflows"
  end

  defp json_errors(%Ecto.Changeset{} = changeset), do: format_errors(changeset)
  defp json_errors(errors) when is_map(errors), do: errors

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
