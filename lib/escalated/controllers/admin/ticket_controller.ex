defmodule Escalated.Controllers.Admin.TicketController do
  @moduledoc """
  Admin ticket controller with full ticket management capabilities.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.TicketDesk
  alias Escalated.Rendering.{UIRenderer, UserDirectory}
  alias Escalated.Schemas.Department
  alias Escalated.Serializers.TicketSerializer
  alias Escalated.Services.{AssignmentService, TicketService}

  def index(conn, params) do
    UIRenderer.render_page(
      conn,
      "Escalated/Admin/Tickets/Index",
      TicketDesk.queue_props(conn, params, "admin")
    )
  end

  def show(conn, %{"reference" => reference}) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        props =
          conn
          |> TicketDesk.show_props(ticket)
          |> Map.merge(%{
            agents: UserDirectory.agents(),
            is_snoozed: TicketSerializer.computed_fields(ticket).is_snoozed
          })

        UIRenderer.render_page(conn, "Escalated/Admin/Tickets/Show", props)
    end
  end

  def follow(conn, params), do: TicketDesk.follow(conn, params, "admin")
  def macro(conn, params), do: TicketDesk.apply_macro(conn, params, "admin")
  def pin(conn, params), do: TicketDesk.pin(conn, params, "admin")
  defdelegate presence(conn, params), to: TicketDesk

  def reply(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <-
           TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: false}) do
      conn |> put_flash(:info, "Reply sent.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, cs} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def note(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <-
           TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: true}) do
      conn |> put_flash(:info, "Note added.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, cs} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def status(conn, %{"reference" => reference, "status" => new_status}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <- TicketService.transition_status(ticket, new_status, actor_id: user.id) do
      conn |> put_flash(:info, "Status updated.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, cs} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def priority(conn, %{"reference" => reference, "priority" => new_priority}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _} <- TicketService.change_priority(ticket, new_priority, actor_id: user.id) do
      conn
      |> put_flash(:info, "Priority updated.")
      |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, cs} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  def assign(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference) do
      result =
        case params["agent_id"] do
          nil -> AssignmentService.unassign(ticket, actor_id: user.id)
          "" -> AssignmentService.unassign(ticket, actor_id: user.id)
          agent_id -> AssignmentService.assign(ticket, agent_id, actor_id: user.id)
        end

      case result do
        {:ok, _} ->
          conn
          |> put_flash(:info, "Assignment updated.")
          |> redirect(to: admin_ticket_path(conn, ticket))

        {:error, cs} ->
          conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
      end
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
    end
  end

  def tags(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference) do
      if params["add_tag_ids"],
        do: TicketService.add_tags(ticket, params["add_tag_ids"], actor_id: user.id)

      if params["remove_tag_ids"],
        do: TicketService.remove_tags(ticket, params["remove_tag_ids"], actor_id: user.id)

      conn |> put_flash(:info, "Tags updated.") |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil -> conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
    end
  end

  # The admin routes for snooze, unsnooze and split pointed here with no such
  # actions. The agent actions answer JSON and redirect nowhere, so they serve
  # the admin screen unchanged; the admin scope's EnsureAdmin still runs first.
  defdelegate snooze(conn, params), to: Escalated.Controllers.Agent.TicketController
  defdelegate unsnooze(conn, params), to: Escalated.Controllers.Agent.TicketController
  defdelegate split(conn, params), to: Escalated.Controllers.Agent.TicketController

  def department(conn, %{"reference" => reference, "department_id" => dept_id}) do
    user = conn.assigns[:current_user]
    repo = Escalated.repo()

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         dept when not is_nil(dept) <- repo.get(Department, dept_id),
         {:ok, _} <- TicketService.change_department(ticket, dept, actor_id: user.id) do
      conn
      |> put_flash(:info, "Department updated.")
      |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Not found"})

      {:error, cs} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
    end
  end

  # Private helpers

  defp admin_ticket_path(conn, ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/tickets/#{ticket.reference}"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
