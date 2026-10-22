defmodule Escalated.Controllers.Agent.TicketController do
  @moduledoc """
  Agent-facing ticket controller with reply, note, status, priority, and assignment actions.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.{FormResponse, TicketDesk}
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.Reply
  alias Escalated.Serializers.TicketSerializer
  alias Escalated.Services.{AssignmentService, TicketActionRegistry, TicketService}

  def index(conn, params) do
    UIRenderer.render_page(
      conn,
      "Escalated/Agent/TicketIndex",
      TicketDesk.queue_props(conn, params, "agent")
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
          |> Map.put(
            :customActions,
            serialize_custom_actions(ticket, conn.assigns[:current_user])
          )

        UIRenderer.render_page(conn, "Escalated/Agent/TicketShow", props)
    end
  end

  @doc """
  Updates the ticket's subject, description and `custom_fields`
  (escalated-laravel's `escalated.agent.tickets.update`).
  """
  def update(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]

    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        case TicketService.update_details(ticket, params, actor_id: user.id) do
          {:ok, _updated} ->
            conn
            |> put_flash(:info, "Ticket updated.")
            |> redirect(to: agent_ticket_path(conn, ticket))

          {:error, errors} ->
            FormResponse.invalid(conn, errors, agent_ticket_path(conn, ticket))
        end
    end
  end

  def follow(conn, params), do: TicketDesk.follow(conn, params, "agent")
  def macro(conn, params), do: TicketDesk.apply_macro(conn, params, "agent")
  def pin(conn, params), do: TicketDesk.pin(conn, params, "agent")
  defdelegate presence(conn, params), to: TicketDesk

  def custom_action(conn, %{"reference" => reference, "action" => action_key} = params) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         action when not is_nil(action) <- TicketActionRegistry.find(action_key),
         true <- TicketActionRegistry.visible?(action, ticket, user) || :not_visible,
         true <- TicketActionRegistry.enabled?(action, ticket, user) || :disabled do
      TicketService.reply(ticket, %{
        body: ~s(Custom action "#{action_key}" was triggered.),
        author_id: user.id,
        is_internal: true
      })

      Escalated.Broadcasting.custom_action_triggered(
        ticket,
        action_key,
        user.id,
        Map.get(params, "payload", %{}),
        TicketActionRegistry.metadata(action, ticket, user)
      )

      conn
      |> put_flash(:info, "Custom action dispatched.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      :disabled ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{error: "Custom action is not enabled"})

      _ ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Custom action not found"})
    end
  end

  def reply(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _reply} <-
           TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: false}) do
      conn
      |> put_flash(:info, "Reply sent.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def note(conn, %{"reference" => reference, "body" => body}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _reply} <-
           TicketService.reply(ticket, %{body: body, author_id: user.id, is_internal: true}) do
      conn
      |> put_flash(:info, "Note added.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
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
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
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
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def assign(conn, %{"reference" => reference, "agent_id" => agent_id}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, _updated} <-
           AssignmentService.assign(ticket, agent_id, actor_id: user.id) do
      conn
      |> put_flash(:info, "Ticket assigned.")
      |> redirect(to: agent_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def snooze(conn, %{"reference" => reference, "snoozed_until" => until_str}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, until, _} <- DateTime.from_iso8601(until_str),
         {:ok, updated} <- TicketService.snooze_ticket(ticket, until, actor_id: user.id) do
      desk_answer(conn, updated, "Ticket snoozed.")
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, :invalid_format} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{error: "Invalid datetime format"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def unsnooze(conn, %{"reference" => reference}) do
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, updated} <- TicketService.unsnooze_ticket(ticket, actor_id: user.id) do
      desk_answer(conn, updated, "Ticket unsnoozed.")
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def split(conn, %{"reference" => reference, "reply_id" => reply_id} = params) do
    user = conn.assigns[:current_user]
    repo = Escalated.repo()

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         reply when not is_nil(reply) <- repo.get(Reply, reply_id),
         true <- reply.ticket_id == ticket.id,
         opts <-
           [actor_id: user.id] ++
             if(params["subject"], do: [subject: params["subject"]], else: []),
         {:ok, new_ticket} <- TicketService.split_ticket(ticket, reply, opts) do
      conn
      |> put_status(201)
      |> Phoenix.Controller.json(%{
        message: "Ticket split successfully.",
        ticket: ticket_list_json(new_ticket)
      })
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket or reply not found"})

      false ->
        conn
        |> put_status(422)
        |> Phoenix.Controller.json(%{error: "Reply does not belong to this ticket"})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  # Private helpers

  # The shared SnoozeButton posts as an Inertia visit, which needs a redirect
  # back to the page; a JSON client still gets the ticket. The admin desk
  # delegates here, so the page to go back to follows the request path.
  defp desk_answer(conn, ticket, message) do
    if get_req_header(conn, "x-inertia") != [] do
      scope =
        if String.contains?(conn.request_path, "/admin/tickets/"), do: "admin", else: "agent"

      conn
      |> put_flash(:info, message)
      |> redirect(to: TicketDesk.ticket_path(scope, ticket))
    else
      Phoenix.Controller.json(conn, %{message: message, ticket: ticket_list_json(ticket)})
    end
  end

  defp agent_ticket_path(conn, ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/agent/tickets/#{ticket.reference}"
  end

  defp serialize_custom_actions(ticket, user) do
    prefix = Escalated.config(:route_prefix, "/support")

    TicketActionRegistry.for_ticket(ticket, user)
    |> Enum.map(fn action ->
      Map.merge(action, %{
        url: "#{prefix}/agent/tickets/#{ticket.reference}/actions/#{action.key}",
        method: "post"
      })
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
    |> Map.merge(TicketSerializer.computed_fields(t))
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
