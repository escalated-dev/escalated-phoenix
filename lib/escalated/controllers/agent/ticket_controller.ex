defmodule Escalated.Controllers.Agent.TicketController do
  @moduledoc """
  Agent-facing ticket controller with reply, note, status, priority, and assignment actions.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Services.{TicketService, AssignmentService}
  alias Escalated.Schemas.{Ticket, Reply}
  alias Escalated.Rendering.UIRenderer
  import Ecto.Query

  def index(conn, params) do
    tickets = TicketService.list(atomize_filters(params))

    UIRenderer.render_page(conn, "Escalated/Agent/Tickets/Index", %{
      tickets: Enum.map(tickets, &ticket_list_json/1),
      filters: params,
      statuses: Ticket.statuses(),
      priorities: Ticket.priorities()
    })
  end

  def show(conn, %{"reference" => reference}) do
    repo = Escalated.repo()

    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        replies = repo.all(from(r in Reply, where: r.ticket_id == ^ticket.id) |> Reply.chronological())
        activities = repo.all(from(a in Escalated.Schemas.TicketActivity, where: a.ticket_id == ^ticket.id) |> Escalated.Schemas.TicketActivity.reverse_chronological() |> limit(50))

        UIRenderer.render_page(conn, "Escalated/Agent/Tickets/Show", %{
          ticket: ticket_detail_json(ticket),
          replies: Enum.map(replies, &reply_json/1),
          activities: Enum.map(activities, &activity_json/1),
          statuses: Ticket.statuses(),
          priorities: Ticket.priorities()
        })
    end
  end

  def reply(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _reply} <- TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: false}) do
      conn
      |> put_flash(:info, "Reply sent.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, changeset} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def note(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _reply} <- TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: true}) do
      conn
      |> put_flash(:info, "Note added.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, changeset} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def status(conn, %{"reference" => reference, "status" => new_status}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _updated} <- TicketService.transition_status(ticket, new_status, actor_id: user.id) do
      conn
      |> put_flash(:info, "Status updated to #{new_status}.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, changeset} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def priority(conn, %{"reference" => reference, "priority" => new_priority}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _updated} <- TicketService.change_priority(ticket, new_priority, actor_id: user.id) do
      conn
      |> put_flash(:info, "Priority updated to #{new_priority}.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, changeset} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def assign(conn, %{"reference" => reference, "agent_id" => agent_id}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _updated} <- AssignmentService.assign(ticket, String.to_integer(agent_id), actor_id: user.id) do
      conn
      |> put_flash(:info, "Ticket assigned.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
      {:error, changeset} -> conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  # Private helpers

  defp agent_ticket_path(conn, ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/agent/tickets/#{ticket.reference}"
  end

  defp atomize_filters(params) do
    params
    |> Map.take(~w(status priority department_id assigned_to search unassigned sla_breached))
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
      id: t.id,
      reference: t.reference,
      subject: t.subject,
      status: t.status,
      priority: t.priority,
      assigned_to: t.assigned_to,
      department_id: t.department_id,
      sla_breached: t.sla_breached,
      created_at: t.inserted_at && DateTime.to_iso8601(t.inserted_at),
      updated_at: t.updated_at && DateTime.to_iso8601(t.updated_at)
    }
  end

  defp ticket_detail_json(t) do
    ticket_list_json(t)
    |> Map.merge(%{
      description: t.description,
      ticket_type: t.ticket_type,
      metadata: t.metadata,
      sla_first_response_due_at: t.sla_first_response_due_at && DateTime.to_iso8601(t.sla_first_response_due_at),
      sla_resolution_due_at: t.sla_resolution_due_at && DateTime.to_iso8601(t.sla_resolution_due_at),
      first_response_at: t.first_response_at && DateTime.to_iso8601(t.first_response_at),
      resolved_at: t.resolved_at && DateTime.to_iso8601(t.resolved_at)
    })
  end

  defp reply_json(r) do
    %{
      id: r.id,
      body: r.body,
      is_internal: r.is_internal,
      is_system: r.is_system,
      is_pinned: r.is_pinned,
      author_id: r.author_id,
      created_at: r.inserted_at && DateTime.to_iso8601(r.inserted_at)
    }
  end

  defp activity_json(a) do
    %{
      id: a.id,
      action: a.action,
      description: a.description,
      causer_id: a.causer_id,
      details: a.details,
      created_at: a.inserted_at && DateTime.to_iso8601(a.inserted_at)
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
