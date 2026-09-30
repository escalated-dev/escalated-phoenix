defmodule Escalated.Channels.TicketChannel do
  @moduledoc """
  Phoenix Channel for real-time ticket updates.

  ## Topics

  - `"escalated:tickets"` - all ticket events (requires agent or admin)
  - `"escalated:ticket:<id>"` - events for a specific ticket
  - `"escalated:agent:<agent_id>"` - events for a specific agent

  ## Authorization

  Join requests are authorized by checking the socket assigns for
  `:current_user` and verifying access via the configured `:agent_check`
  function. The all-tickets topic requires agent/admin access.
  Ticket-specific topics require the user to be the requester or an agent.

  With merchant tenancy enabled the authenticated host socket must assign
  `:escalated_tenant_id`. Topics use `Escalated.Tenancy.topic/1`; legacy topics
  are refused. Membership and topic access are checked again before delivery.
  """
  use Phoenix.Channel

  alias Escalated.Channels.TenantSocket
  alias Escalated.Schemas.Ticket

  @impl true
  def join(topic, params, socket) do
    TenantSocket.run(
      socket,
      fn ->
        topic
        |> TenantSocket.canonical_topic()
        |> do_join(params, socket)
        |> TenantSocket.remember(topic)
      end,
      {:error, %{reason: "unauthorized"}}
    )
  end

  defp do_join("escalated:tickets", _params, socket) do
    if authorized_agent?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp do_join("escalated:ticket:" <> ticket_id, _params, socket) do
    # Allow agents and the ticket's requester. Being signed in is not enough:
    # the topic carries every event for the ticket.
    if Escalated.Tenancy.enabled?() do
      with %Ticket{} = ticket <- find_ticket(ticket_id),
           true <-
             authorized_agent?(socket) or requester_ticket?(ticket, socket.assigns[:current_user]) do
        {:ok, socket}
      else
        _ -> {:error, %{reason: "unauthorized"}}
      end
    else
      if authorized_agent?(socket) || requester?(ticket_id, socket.assigns[:current_user]),
        do: {:ok, socket},
        else: {:error, %{reason: "unauthorized"}}
    end
  end

  defp do_join("escalated:agent:" <> agent_id, _params, socket) do
    user = socket.assigns[:current_user]

    if authorized_agent?(socket) && to_string(Map.get(user, :id, Map.get(user, "id"))) == agent_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp do_join(_topic, _params, _socket) do
    {:error, %{reason: "invalid topic"}}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    deliver(socket, fn -> {:noreply, socket} end)
  end

  @impl true
  def handle_info(%{event: event, payload: payload}, socket) do
    deliver(socket, fn ->
      if authorized_agent?(socket) do
        push(socket, event, payload)
      else
        case customer_payload(event, payload) do
          {:ok, safe} -> push(socket, event, safe)
          :skip -> :ok
        end
      end

      {:noreply, socket}
    end)
  end

  defp deliver(socket, callback) do
    TenantSocket.run(
      socket,
      fn ->
        if joined_access?(socket),
          do: callback.(),
          else: {:stop, :normal, socket}
      end,
      {:stop, :normal, socket}
    )
  end

  defp joined_access?(socket) do
    topic = socket |> TenantSocket.joined_topic() |> TenantSocket.canonical_topic()
    match?({:ok, _}, do_join(topic, %{}, socket))
  end

  # Private

  # True when `user` requested the ticket the topic names. A topic id that is
  # not a number, or names no ticket, names no requester. Ids are compared as
  # strings: the column follows :user_key_type, the host's id its own schema.
  defp requester?(_ticket_id, user) when not is_map(user), do: false

  defp requester?(ticket_id, user) do
    case find_ticket(ticket_id) do
      %Ticket{} = ticket -> requester_ticket?(ticket, user)
      _ -> false
    end
  end

  defp find_ticket(ticket_id) do
    with {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(ticket_id),
         %Ticket{} = ticket <-
           Escalated.repo().get(Ticket, id) do
      ticket
    else
      _ -> nil
    end
  end

  defp requester_ticket?(ticket, user), do: Escalated.TicketAccess.requester?(ticket, user)

  # Generic ticket events include internal notes and host-defined action data.
  # Requesters get only the small public update contract, never raw payloads.
  defp customer_payload("ticket:reply_added", %{is_internal: false} = payload),
    do: {:ok, Map.take(payload, [:ticket_id, :reference, :reply_id, :author_id])}

  defp customer_payload("ticket:status_changed", payload) when is_map(payload),
    do: {:ok, Map.take(payload, [:ticket_id, :reference, :from, :to])}

  defp customer_payload("ticket:priority_changed", payload) when is_map(payload),
    do: {:ok, Map.take(payload, [:ticket_id, :reference, :from, :to])}

  defp customer_payload("ticket:created", payload) when is_map(payload),
    do: {:ok, Map.take(payload, [:ticket_id, :reference, :subject, :status, :priority])}

  defp customer_payload(_, _), do: :skip

  defp authorized_agent?(socket) do
    Escalated.Permissions.agent?(socket.assigns[:current_user])
  end
end
