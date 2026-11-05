defmodule Escalated.Controllers.Agent.TicketController do
  @moduledoc """
  Agent-facing ticket controller with reply, note, status, priority, and assignment actions.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2, where: 3]

  alias Escalated.AgentPanel
  alias Escalated.Controllers.{AgentInbox, FormResponse, TicketDesk}
  alias Escalated.Rendering.{UIRenderer, UserDirectory}
  alias Escalated.Schemas.{Reply, Ticket}
  alias Escalated.Serializers.TicketSerializer
  alias Escalated.Services.{AssignmentService, TicketActionRegistry, TicketService}

  def index(conn, params) do
    agent = conn.assigns[:current_user]

    case AgentInbox.validate(params) do
      :ok ->
        filters = AgentInbox.normalise(params, agent)
        queue = AgentInbox.queue_for(filters, agent)
        conn = AgentInbox.remember(conn, queue)

        props =
          conn
          |> TicketDesk.queue_props(params, "agent", AgentInbox.list_filters(filters, queue))
          |> Map.update!(:tickets, &with_panel_fields(&1, agent))
          |> Map.merge(%{
            queue: AgentInbox.queue_prop(queue),
            inbox: AgentInbox.inbox(agent, queue)
          })

        UIRenderer.render_page(conn, "Escalated/Agent/TicketIndex", props)

      {:error, errors} ->
        FormResponse.invalid_visit(conn, errors, "#{TicketDesk.prefix()}/agent/tickets")
    end
  end

  def show(conn, %{"reference" => reference}) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        agent = conn.assigns[:current_user]
        queue = AgentInbox.recalled(conn, agent)

        # Opening the ticket in the agent panel is reading it.
        AgentPanel.mark_read(agent.id, ticket)
        panel = Map.fetch!(AgentPanel.row_fields(agent, [ticket]), ticket.id)

        props =
          conn
          |> TicketDesk.show_props(ticket)
          |> Map.update!(:ticket, &Map.put(&1, :requester_tickets, requester_tickets(ticket)))
          |> Map.update!(:ticket, &Map.merge(&1, panel))
          |> Map.put(:customActions, serialize_custom_actions(ticket, agent))
          |> Map.put(:agents, UserDirectory.assignable_agents(ticket))
          |> Map.merge(%{
            queue: AgentInbox.queue_prop(queue),
            inbox: AgentInbox.inbox(agent, queue)
          })

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

  @doc """
  `escalated.agent.tickets.read` / `.unread`: marks the ticket read or unread
  for the agent. Answers `{is_unread}`; an Inertia visit goes back.
  """
  def read(conn, params), do: mark(conn, params, false)
  def unread(conn, params), do: mark(conn, params, true)

  defp mark(conn, %{"reference" => reference}, unread?) do
    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        agent = conn.assigns[:current_user]

        if unread?,
          do: AgentPanel.mark_unread(agent.id, ticket),
          else: AgentPanel.mark_read(agent.id, ticket)

        FormResponse.json_or_back(conn, %{is_unread: unread?}, agent_ticket_path(conn, ticket))
    end
  end

  # is_unread and the requester's presence on every row (ADR
  # 2026-11-05-agent-panel-data): one query each for the page.
  defp with_panel_fields(%{data: rows} = page, agent) do
    ids = Enum.map(rows, & &1.id)
    tickets = Escalated.repo().all(from(t in Ticket, where: t.id in ^ids))
    fields = AgentPanel.row_fields(agent, tickets)

    %{page | data: Enum.map(rows, &Map.merge(&1, Map.get(fields, &1.id, %{})))}
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

  @doc """
  Snoozes the ticket until `snoozed_until`, which must be a date in the
  future (escalated-laravel's `SnoozeTicketRequest`). The admin desk
  delegates here.
  """
  def snooze(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]

    case TicketService.find(reference) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket ->
        with {:ok, until} <- snooze_until(params["snoozed_until"]),
             {:ok, updated} <- TicketService.snooze_ticket(ticket, until, actor_id: user.id) do
          desk_answer(conn, updated, "Ticket snoozed.")
        else
          {:error, errors} ->
            FormResponse.invalid(conn, errors, TicketDesk.ticket_path(desk_scope(conn), ticket))
        end
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

  # `snoozed_until`: required, a date (ISO 8601; a time without an offset is
  # UTC), strictly in the future.
  defp snooze_until(value) when is_binary(value) and value != "" do
    parsed =
      case DateTime.from_iso8601(value) do
        {:ok, until, _offset} ->
          {:ok, until}

        _ ->
          case NaiveDateTime.from_iso8601(value) do
            {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
            _ -> :error
          end
      end

    case parsed do
      {:ok, until} ->
        if DateTime.compare(until, DateTime.utc_now()) == :gt,
          do: {:ok, DateTime.truncate(until, :second)},
          else: {:error, %{"snoozed_until" => ["The snooze time must be in the future."]}}

      :error ->
        {:error, %{"snoozed_until" => ["The snooze time must be a valid date."]}}
    end
  end

  defp snooze_until(_value),
    do: {:error, %{"snoozed_until" => ["The snooze time is required."]}}

  # The requester's five most recent other tickets, matched as
  # `requester_ticket_count` is and read through the visibility-scoped repo.
  defp requester_tickets(ticket) do
    query = from(t in Ticket, where: t.id != ^ticket.id)

    query =
      cond do
        not is_nil(ticket.requester_id) and is_nil(ticket.requester_type) ->
          where(query, [t], t.requester_id == ^ticket.requester_id and is_nil(t.requester_type))

        not is_nil(ticket.requester_id) ->
          where(
            query,
            [t],
            t.requester_id == ^ticket.requester_id and t.requester_type == ^ticket.requester_type
          )

        is_binary(ticket.guest_email) and ticket.guest_email != "" ->
          where(query, [t], t.guest_email == ^ticket.guest_email)

        true ->
          nil
      end

    if query do
      from(t in query, order_by: [desc: t.inserted_at, desc: t.id], limit: 5)
      |> Escalated.repo().all()
      |> Enum.map(fn other ->
        %{
          id: other.id,
          reference: other.reference,
          subject: other.subject,
          status: to_string(other.status),
          created_at: other.inserted_at && DateTime.to_iso8601(other.inserted_at),
          updated_at: other.updated_at && DateTime.to_iso8601(other.updated_at)
        }
      end)
    else
      []
    end
  end

  # The admin desk: {prefix}/admin/tickets/..., or the embedded admin under the
  # host's prefix (ADR 2026-11-05-embeddable-admin).
  defp desk_scope(conn) do
    if Escalated.Embed.embedded?(conn) or String.contains?(conn.request_path, "/admin/tickets/"),
      do: "admin",
      else: "agent"
  end

  # The shared SnoozeButton posts as an Inertia visit, which needs a redirect
  # back to the page; a JSON client still gets the ticket. The admin desk
  # delegates here, so the page to go back to follows the request path.
  defp desk_answer(conn, ticket, message) do
    if get_req_header(conn, "x-inertia") != [] do
      conn
      |> put_flash(:info, message)
      |> redirect(to: TicketDesk.ticket_path(desk_scope(conn), ticket))
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
