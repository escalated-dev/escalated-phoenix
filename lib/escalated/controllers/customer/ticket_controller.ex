defmodule Escalated.Controllers.Customer.TicketController do
  @moduledoc """
  Customer-facing ticket controller.

  Allows authenticated users to view their own tickets, create new ones,
  and reply to existing tickets.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.{Paginator, TicketPresenter, UIRenderer}
  alias Escalated.Schemas.Ticket
  alias Escalated.Services.TicketService
  alias Escalated.TicketAccess

  def index(conn, params) do
    user = conn.assigns[:current_user]

    tickets =
      case TicketAccess.user_id(user) do
        # Nobody signed in owns no tickets. An unfiltered list is every
        # customer's tickets.
        nil ->
          []

        user_id ->
          TicketService.list(%{requester_id: user_id, status: params["status"]})
          |> Enum.filter(&TicketAccess.requester?(&1, user))
      end

    path = Escalated.config(:route_prefix, "/support") <> "/tickets"

    UIRenderer.render_page(conn, "Escalated/Customer/Index", %{
      tickets: tickets |> Paginator.paginate(params, path, &TicketPresenter.customer_row/1),
      filters: Map.take(params, ~w(status priority ticket_type search sort_by sort_dir))
    })
  end

  def new(conn, _params) do
    departments =
      Escalated.repo().all(
        Escalated.Schemas.Department.active()
        |> Escalated.Schemas.Department.ordered()
      )

    UIRenderer.render_page(conn, "Escalated/Customer/Create", %{
      departments: Enum.map(departments, &%{id: &1.id, name: &1.name}),
      priorities: Ticket.priorities()
    })
  end

  # The shared Create page posts its fields at the top level; older clients
  # nest them under "ticket". Both are read.
  def create(conn, %{"ticket" => ticket_params}) when is_map(ticket_params),
    do: create_ticket(conn, ticket_params)

  def create(conn, %{"subject" => _} = params), do: create_ticket(conn, params)

  def create(conn, _params) do
    conn |> put_status(422) |> Phoenix.Controller.json(%{error: "A ticket object is required"})
  end

  defp create_ticket(conn, ticket_params) do
    case TicketAccess.user_id(conn.assigns[:current_user]) do
      nil ->
        conn |> put_status(401) |> Phoenix.Controller.json(%{error: "Authentication required"})

      user_id ->
        create_for_requester(conn, ticket_params, user_id)
    end
  end

  defp create_for_requester(conn, ticket_params, user_id) do
    customer_fields =
      Map.take(ticket_params, ~w(subject description priority ticket_type department_id))

    attrs =
      customer_fields
      |> Map.put("requester_id", user_id)
      |> Map.put("requester_type", to_string(Escalated.user_schema()))

    case TicketService.create(attrs) do
      {:ok, ticket} ->
        conn
        |> put_flash(:info, "Ticket created successfully.")
        |> redirect(to: ticket_path(conn, ticket))

      {:error, changeset} ->
        UIRenderer.render_page(conn, "Escalated/Customer/Create", %{
          errors: format_errors(changeset),
          ticket: customer_fields
        })
    end
  end

  def show(conn, %{"reference" => reference}) do
    case find_own_ticket(reference, conn.assigns[:current_user]) do
      {:error, status, message} ->
        conn |> put_status(status) |> Phoenix.Controller.json(%{error: message})

      {:ok, ticket} ->
        UIRenderer.render_page(conn, "Escalated/Customer/Show", %{
          ticket: TicketPresenter.customer_detail(ticket),
          allow_close: Escalated.config(:allow_customer_close, true)
        })
    end
  end

  @doc "Close the requester's own ticket, when `allow_customer_close` is on."
  def close(conn, %{"reference" => reference}) do
    if Escalated.config(:allow_customer_close, true) do
      change_own_status(conn, reference, "closed", "Ticket closed.")
    else
      conn
      |> put_status(403)
      |> Phoenix.Controller.json(%{error: "Customers cannot close tickets"})
    end
  end

  @doc "Reopen the requester's own ticket."
  def reopen(conn, %{"reference" => reference}),
    do: change_own_status(conn, reference, "reopened", "Ticket reopened.")

  defp change_own_status(conn, reference, status, message) do
    user = conn.assigns[:current_user]

    with {:ok, ticket} <- find_own_ticket(reference, user),
         {:ok, _} <-
           TicketService.transition_status(ticket, status, actor_id: TicketAccess.user_id(user)) do
      conn |> put_flash(:info, message) |> redirect(to: ticket_path(conn, ticket))
    else
      {:error, status, message} when is_integer(status) ->
        conn |> put_status(status) |> Phoenix.Controller.json(%{error: message})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def reply(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    case find_own_ticket(reference, user) do
      {:error, status, message} ->
        conn |> put_status(status) |> Phoenix.Controller.json(%{error: message})

      {:ok, ticket} ->
        case TicketService.reply(ticket, %{
               body: body,
               author_id: TicketAccess.user_id(user),
               is_internal: false
             }) do
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

  # The ticket named in the URL, provided the signed-in user requested it. The
  # lookup takes a reference or a numeric id and nothing else, so without this
  # check any customer could open any ticket by counting ids. 404 when there is
  # no such ticket, 403 when it is someone else's -- the answer the Laravel and
  # NestJS customer controllers give.
  defp find_own_ticket(reference, user) do
    case TicketService.find(reference) do
      nil ->
        {:error, 404, "Ticket not found"}

      ticket ->
        if TicketAccess.requester?(ticket, user),
          do: {:ok, ticket},
          else: {:error, 403, "You can only access your own tickets"}
    end
  end

  defp ticket_path(conn, ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/tickets/#{ticket.reference}"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
