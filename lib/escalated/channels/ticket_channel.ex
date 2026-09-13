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
  """
  use Phoenix.Channel

  alias Escalated.Schemas.Ticket

  @impl true
  def join("escalated:tickets", _params, socket) do
    if authorized_agent?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("escalated:ticket:" <> ticket_id, _params, socket) do
    # Allow agents and the ticket's requester. Being signed in is not enough:
    # the topic carries every event for the ticket.
    if authorized_agent?(socket) || requester?(ticket_id, socket.assigns[:current_user]) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("escalated:agent:" <> agent_id, _params, socket) do
    user = socket.assigns[:current_user]

    if user && to_string(user.id) == agent_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join(_topic, _params, _socket) do
    {:error, %{reason: "invalid topic"}}
  end

  @impl true
  def handle_info(%{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  # Private

  # True when `user` requested the ticket the topic names. A topic id that is
  # not a number, or names no ticket, names no requester. Ids are compared as
  # strings: the column follows :user_key_type, the host's id its own schema.
  defp requester?(_ticket_id, nil), do: false

  defp requester?(ticket_id, user) do
    with {id, ""} <- Integer.parse(ticket_id),
         %Ticket{requester_id: requester_id} when not is_nil(requester_id) <-
           Escalated.repo().get(Ticket, id) do
      to_string(requester_id) == to_string(Map.get(user, :id))
    else
      _ -> false
    end
  end

  defp authorized_agent?(socket) do
    user = socket.assigns[:current_user]
    check_fn = Escalated.config(:agent_check)

    cond do
      is_nil(user) -> false
      is_function(check_fn, 1) -> check_fn.(user)
      is_nil(check_fn) -> true
      true -> false
    end
  end
end
