defmodule Escalated.Controllers.Customer.TicketController do
  @moduledoc """
  Customer-facing ticket controller.

  Allows authenticated users to view their own tickets, create new ones,
  and reply to existing tickets.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Services.TicketService
  alias Escalated.Schemas.Ticket
  alias Escalated.Rendering.UIRenderer

  def index(conn, params) do
    user = conn.assigns[:current_user]

    tickets =
      TicketService.list(%{
        requester_id: user && user.id,
        status: params["status"]
      })

    UIRenderer.render_page(conn, "Escalated/Customer/Tickets/Index", %{
      tickets: Enum.map(tickets, &ticket_json/1),
      filters: %{status: params["status"]}
    })
  end

  def new(conn, _params) do
    departments =
      Escalated.repo().all(
        Escalated.Schemas.Department.active()
        |> Escalated.Schemas.Department.ordered()
      )

    UIRenderer.render_page(conn, "Escalated/Customer/Tickets/New", %{
      departments: Enum.map(departments, &%{id: &1.id, name: &1.name}),
      priorities: Ticket.priorities()
    })
  end

  def create(conn, %{"ticket" => ticket_params}) do
    user = conn.assigns[:current_user]

    attrs =
      ticket_params
      |> Map.put("requester_id", user && user.id)
      |> Map.put("requester_type", if(user, do: to_string(Escalated.user_schema()), else: nil))

    case TicketService.create(attrs) do
      {:ok, ticket} ->
        conn
        |> put_flash(:info, "Ticket created successfully.")
        |> redirect(to: ticket_path(conn, ticket))

      {:error, changeset} ->
        UIRenderer.render_page(conn, "Escalated/Customer/Tickets/New", %{
          errors: format_errors(changeset),
          ticket: ticket_params
        })
    end
  end

  def show(conn, %{"reference" => reference}) do
    user = conn.assigns[:current_user]
    ticket = TicketService.find(reference)

    case ticket do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        repo = Escalated.repo()
        replies = repo.all(Escalated.Schemas.Reply.chronological() |> Ecto.Query.where([r], r.ticket_id == ^ticket.id and r.is_internal == false))

        UIRenderer.render_page(conn, "Escalated/Customer/Tickets/Show", %{
          ticket: ticket_detail_json(ticket),
          replies: Enum.map(replies, &reply_json/1),
          allow_close: Escalated.config(:allow_customer_close, true)
        })
    end
  end

  def reply(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]
    ticket = TicketService.find(reference)

    case ticket do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        case TicketService.reply(ticket, %{body: body, author_id: user && user.id, is_internal: false}) do
          {:ok, _reply} ->
            conn
            |> put_flash(:info, "Reply sent.")
            |> redirect(to: ticket_path(conn, ticket))

          {:error, changeset} ->
            conn
            |> put_status(422)
            |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
        end
    end
  end

  # Private helpers

  defp ticket_path(conn, ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/tickets/#{ticket.reference}"
  end

  defp ticket_json(ticket) do
    %{
      id: ticket.id,
      reference: ticket.reference,
      subject: ticket.subject,
      status: ticket.status,
      priority: ticket.priority,
      created_at: ticket.inserted_at && DateTime.to_iso8601(ticket.inserted_at),
      updated_at: ticket.updated_at && DateTime.to_iso8601(ticket.updated_at)
    }
  end

  defp ticket_detail_json(ticket) do
    ticket_json(ticket)
    |> Map.merge(%{
      description: ticket.description,
      ticket_type: ticket.ticket_type,
      department_id: ticket.department_id
    })
  end

  defp reply_json(reply) do
    %{
      id: reply.id,
      body: reply.body,
      is_internal: reply.is_internal,
      author_id: reply.author_id,
      created_at: reply.inserted_at && DateTime.to_iso8601(reply.inserted_at)
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
