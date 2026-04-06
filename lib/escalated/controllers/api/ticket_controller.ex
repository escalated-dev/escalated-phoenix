defmodule Escalated.Controllers.Api.TicketController do
  @moduledoc """
  JSON API controller for tickets. Used by external integrations and the desktop app.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Services.{TicketService, AssignmentService}

  def index(conn, params) do
    tickets =
      TicketService.list(%{
        status: params["status"],
        priority: params["priority"],
        department_id: params["department_id"],
        assigned_to: params["assigned_to"],
        search: params["search"]
      })

    json(conn, %{
      data:
        Enum.map(tickets, fn t ->
          %{
            id: t.id,
            reference: t.reference,
            subject: t.subject,
            status: t.status,
            priority: t.priority,
            ticket_type: t.ticket_type,
            assigned_to: t.assigned_to,
            department_id: t.department_id,
            sla_breached: t.sla_breached,
            created_at: t.inserted_at && DateTime.to_iso8601(t.inserted_at),
            updated_at: t.updated_at && DateTime.to_iso8601(t.updated_at)
          }
        end)
    })
  end

  def show(conn, %{"reference" => reference}) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      ticket ->
        json(conn, %{data: ticket_json(ticket)})
    end
  end

  def create(conn, %{"ticket" => params}) do
    case TicketService.create(params) do
      {:ok, ticket} ->
        conn |> put_status(201) |> json(%{data: ticket_json(ticket)})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{errors: format_errors(changeset)})
    end
  end

  def reply(conn, %{"reference" => reference, "body" => body} = params) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      ticket ->
        attrs = %{
          body: body,
          author_id: params["author_id"],
          is_internal: params["is_internal"] == true
        }

        case TicketService.reply(ticket, attrs) do
          {:ok, reply} ->
            conn |> put_status(201) |> json(%{data: %{id: reply.id, body: reply.body}})

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{errors: format_errors(changeset)})
        end
    end
  end

  def status(conn, %{"reference" => reference, "status" => new_status}) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      ticket ->
        case TicketService.transition_status(ticket, new_status) do
          {:ok, updated} -> json(conn, %{data: ticket_json(updated)})
          {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  def priority(conn, %{"reference" => reference, "priority" => new_priority}) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      ticket ->
        case TicketService.change_priority(ticket, new_priority) do
          {:ok, updated} -> json(conn, %{data: ticket_json(updated)})
          {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  def assign(conn, %{"reference" => reference, "agent_id" => agent_id}) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      ticket ->
        case AssignmentService.assign(ticket, agent_id) do
          {:ok, updated} -> json(conn, %{data: ticket_json(updated)})
          {:error, cs} -> conn |> put_status(422) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  defp ticket_json(t) do
    %{
      id: t.id,
      reference: t.reference,
      subject: t.subject,
      description: t.description,
      status: t.status,
      priority: t.priority,
      ticket_type: t.ticket_type,
      assigned_to: t.assigned_to,
      department_id: t.department_id,
      sla_breached: t.sla_breached,
      sla_first_response_due_at: t.sla_first_response_due_at && DateTime.to_iso8601(t.sla_first_response_due_at),
      sla_resolution_due_at: t.sla_resolution_due_at && DateTime.to_iso8601(t.sla_resolution_due_at),
      created_at: t.inserted_at && DateTime.to_iso8601(t.inserted_at),
      updated_at: t.updated_at && DateTime.to_iso8601(t.updated_at)
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
