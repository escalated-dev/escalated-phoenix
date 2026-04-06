defmodule Escalated.Controllers.Admin.TicketController do
  @moduledoc """
  Admin ticket controller with full ticket management capabilities.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Services.{TicketService, AssignmentService}
  alias Escalated.Schemas.{Ticket, Reply, Department, Tag, TicketActivity}
  alias Escalated.Rendering.UIRenderer
  import Ecto.Query

  def index(conn, params) do
    repo = Escalated.repo()
    tickets = TicketService.list(atomize_filters(params))

    departments = repo.all(Department.active() |> Department.ordered())
    tags = repo.all(Tag.ordered())

    UIRenderer.render_page(conn, "Escalated/Admin/Tickets/Index", %{
      tickets: Enum.map(tickets, &ticket_list_json/1),
      meta: %{total: length(tickets)},
      filters: params,
      departments: Enum.map(departments, &%{id: &1.id, name: &1.name}),
      tags: Enum.map(tags, &%{id: &1.id, name: &1.name, color: &1.color}),
      statuses: Ticket.statuses(),
      priorities: Ticket.priorities(),
      ticket_types: Ticket.ticket_types()
    })
  end

  def show(conn, %{"reference" => reference}) do
    repo = Escalated.repo()

    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        replies = repo.all(from(r in Reply, where: r.ticket_id == ^ticket.id) |> Reply.chronological())
        activities = repo.all(from(a in TicketActivity, where: a.ticket_id == ^ticket.id) |> TicketActivity.reverse_chronological() |> limit(50))
        departments = repo.all(Department.active() |> Department.ordered())
        tags = repo.all(Tag.ordered())

        UIRenderer.render_page(conn, "Escalated/Admin/Tickets/Show", %{
          ticket: ticket_detail_json(ticket),
          replies: Enum.map(replies, &reply_json/1),
          activities: Enum.map(activities, &activity_json/1),
          departments: Enum.map(departments, &%{id: &1.id, name: &1.name}),
          tags: Enum.map(tags, &%{id: &1.id, name: &1.name, color: &1.color}),
          statuses: Ticket.statuses(),
          priorities: Ticket.priorities()
        })
    end
  end

  def reply(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <- TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: false}) do
      conn |> put_flash(:info, "Reply sent.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, cs} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def note(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <- TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: true}) do
      conn |> put_flash(:info, "Note added.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, cs} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def status(conn, %{"reference" => reference, "status" => new_status}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <- TicketService.transition_status(ticket, new_status, actor_id: user.id) do
      conn |> put_flash(:info, "Status updated.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, cs} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def priority(conn, %{"reference" => reference, "priority" => new_priority}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <- TicketService.change_priority(ticket, new_priority, actor_id: user.id) do
      conn |> put_flash(:info, "Priority updated.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, cs} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def assign(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference) do
      result =
        case params["agent_id"] do
          nil -> AssignmentService.unassign(ticket, actor_id: user.id)
          "" -> AssignmentService.unassign(ticket, actor_id: user.id)
          agent_id -> AssignmentService.assign(ticket, String.to_integer(agent_id), actor_id: user.id)
        end

      case result do
        {:ok, _} -> conn |> put_flash(:info, "Assignment updated.") |> redirect(to: admin_ticket_path(conn, ticket))
        {:error, cs} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
      end
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
    end
  end

  def tags(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference) do
      if params["add_tag_ids"], do: TicketService.add_tags(ticket, params["add_tag_ids"], actor_id: user.id)
      if params["remove_tag_ids"], do: TicketService.remove_tags(ticket, params["remove_tag_ids"], actor_id: user.id)

      conn |> put_flash(:info, "Tags updated.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
    end
  end

  def department(conn, %{"reference" => reference, "department_id" => dept_id}) do
    user = conn.assigns[:current_user]
    repo = Escalated.repo()

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         dept when not is_nil(dept) <- repo.get(Department, dept_id),
         {:ok, _} <- TicketService.change_department(ticket, dept, actor_id: user.id) do
      conn |> put_flash(:info, "Department updated.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Not found"})
      {:error, cs} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  # Private helpers

  defp admin_ticket_path(conn, ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/tickets/#{ticket.reference}"
  end

  defp atomize_filters(params) do
    params
    |> Map.take(~w(status priority department_id assigned_to search unassigned sla_breached ticket_type))
    |> Enum.reduce(%{}, fn
      {_key, ""}, acc -> acc
      {_key, nil}, acc -> acc
      {"unassigned", "true"}, acc -> Map.put(acc, :unassigned, true)
      {"sla_breached", "true"}, acc -> Map.put(acc, :sla_breached, true)
      {key, val}, acc -> Map.put(acc, String.to_existing_atom(key), val)
    end)
  end

  defp ticket_list_json(t) do
    %{
      id: t.id, reference: t.reference, subject: t.subject,
      status: t.status, priority: t.priority, ticket_type: t.ticket_type,
      assigned_to: t.assigned_to, department_id: t.department_id,
      sla_breached: t.sla_breached,
      created_at: t.inserted_at && DateTime.to_iso8601(t.inserted_at),
      updated_at: t.updated_at && DateTime.to_iso8601(t.updated_at)
    }
  end

  defp ticket_detail_json(t) do
    ticket_list_json(t) |> Map.merge(%{
      description: t.description, metadata: t.metadata,
      sla_policy_id: t.sla_policy_id,
      sla_first_response_due_at: t.sla_first_response_due_at && DateTime.to_iso8601(t.sla_first_response_due_at),
      sla_resolution_due_at: t.sla_resolution_due_at && DateTime.to_iso8601(t.sla_resolution_due_at),
      first_response_at: t.first_response_at && DateTime.to_iso8601(t.first_response_at),
      resolved_at: t.resolved_at && DateTime.to_iso8601(t.resolved_at),
      closed_at: t.closed_at && DateTime.to_iso8601(t.closed_at)
    })
  end

  defp reply_json(r) do
    %{id: r.id, body: r.body, is_internal: r.is_internal, is_system: r.is_system,
      is_pinned: r.is_pinned, author_id: r.author_id,
      created_at: r.inserted_at && DateTime.to_iso8601(r.inserted_at)}
  end

  defp activity_json(a) do
    %{id: a.id, action: a.action, description: a.description,
      causer_id: a.causer_id, details: a.details,
      created_at: a.inserted_at && DateTime.to_iso8601(a.inserted_at)}
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
