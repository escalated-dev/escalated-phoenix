defmodule Escalated.Services.WebhookEvents do
  @moduledoc """
  Bridges core ticket lifecycle events to outbound webhook dispatch.

  Mirrors the Laravel `Escalated\\Laravel\\Listeners\\DispatchWebhook`: it maps
  a domain event to its wire event name and builds the JSON-serializable
  payload, then hands off to `Escalated.Services.WebhookDispatcher`.

  Called from `Escalated.Services.TicketService` at the same call sites as the
  `Escalated.Plugins.Hooks.do_action/2` dispatches, so a webhook fires for the
  subset of events Phoenix already emits.

  ## Event names

    * `ticket.created`, `ticket.status_changed`, `ticket.resolved`,
      `ticket.closed`, `ticket.reopened`, `ticket.priority_changed`
    * `reply.created` (public reply), `note.created` (internal note)

  ## Payload shape

    * ticket events: `%{ticket: %{id, reference, subject, status, priority}}`
    * reply/note events: `%{ticket: %{id, reference}, reply: %{id, is_internal_note}}`

  Optional `:tag` (`%{id, name}`) and `:agent_id` keys are included when present
  in the context, matching the reference payload builder.
  """

  alias Escalated.Services.WebhookDispatcher

  @doc """
  Dispatch a webhook `event` built from a context map.

  The context may carry `:ticket`, `:reply`, `:tag` and `:agent_id`; the payload
  is assembled from whichever are present (see the moduledoc).
  """
  def dispatch(event, context) when is_binary(event) and is_map(context) do
    WebhookDispatcher.dispatch(event, build_payload(context))
  end

  @doc "Build the wire payload from a context map (mirrors DispatchWebhook)."
  def build_payload(context) do
    %{}
    |> put_ticket(context)
    |> put_reply(context)
    |> put_tag(Map.get(context, :tag))
    |> put_agent(Map.get(context, :agent_id))
  end

  # A reply present means the ticket portion is trimmed to {id, reference},
  # matching the reference listener; otherwise emit the full ticket snapshot.
  defp put_ticket(payload, %{reply: _reply, ticket: ticket}) when not is_nil(ticket) do
    Map.put(payload, :ticket, %{id: ticket.id, reference: ticket.reference})
  end

  defp put_ticket(payload, %{ticket: ticket}) when not is_nil(ticket) do
    Map.put(payload, :ticket, %{
      id: ticket.id,
      reference: ticket.reference,
      subject: ticket.subject,
      status: ticket.status,
      priority: ticket.priority
    })
  end

  defp put_ticket(payload, _context), do: payload

  defp put_reply(payload, %{reply: reply}) when not is_nil(reply) do
    Map.put(payload, :reply, %{id: reply.id, is_internal_note: reply.is_internal})
  end

  defp put_reply(payload, _context), do: payload

  defp put_tag(payload, nil), do: payload
  defp put_tag(payload, tag), do: Map.put(payload, :tag, %{id: tag.id, name: tag.name})

  defp put_agent(payload, nil), do: payload
  defp put_agent(payload, agent_id), do: Map.put(payload, :agent_id, agent_id)
end
