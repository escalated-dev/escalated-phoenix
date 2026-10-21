defmodule Escalated.Events do
  @moduledoc """
  The domain event names, and the one place a ticket event is announced.

  The names are fixed by escalated-developer-context
  `decisions/2026-10-21-event-vocabulary.md`. Every backend emits the same
  canonical names to outbound webhooks and workflow triggers.

  ## Legacy names

  Names other backends (or older versions) used are accepted wherever stored
  data is **read**: a saved workflow's `trigger_event` and a webhook's
  subscribed `events`. They are treated as their canonical name, stored under
  it when a form posts them, and never emitted or offered.

  ## Emitting

  `emit/2` sends an event to the webhooks subscribed to it
  (`Escalated.Services.WebhookEvents`) and, when the context carries a ticket,
  runs the workflows saved against it (`Escalated.Services.WorkflowRunner`).
  Webhooks and workflows therefore see exactly the same events. Neither can
  break the operation that emitted the event: webhook dispatch and the
  workflow runner both log and swallow their own failures.
  """

  alias Escalated.Notifications
  alias Escalated.Schemas.Ticket
  alias Escalated.Services.{WebhookEvents, WorkflowRunner}

  @canonical ~w(
    ticket.created ticket.updated ticket.status_changed
    ticket.resolved ticket.closed ticket.reopened
    ticket.assigned ticket.unassigned ticket.escalated
    ticket.priority_changed ticket.department_changed
    ticket.tag_added ticket.tag_removed
    reply.created note.created
    sla.warning sla.breached
    chat.started chat.assigned chat.transferred chat.message chat.ended
  )

  # What this package emits today. Live chat events are canonical but have no
  # emit site here yet, so they are neither offered nor fired.
  @emitted @canonical -- ~w(chat.started chat.assigned chat.transferred chat.message chat.ended)

  @legacy %{
    "ticket.replied" => "reply.created",
    "internal_note.added" => "note.created",
    "internal_note.created" => "note.created",
    "tag.added" => "ticket.tag_added",
    "ticket.tagged" => "ticket.tag_added",
    "tag.removed" => "ticket.tag_removed",
    "ticket.untagged" => "ticket.tag_removed",
    "chat.session_started" => "chat.started",
    "chat.session_ended" => "chat.ended"
  }

  @doc "Every canonical event name."
  def canonical_names, do: @canonical

  @doc "The canonical names this package emits (and offers in its forms)."
  def emitted, do: @emitted

  @doc "Legacy name => canonical name."
  def legacy_aliases, do: @legacy

  @doc "The canonical name for `name` (itself when it is not a legacy name)."
  def canonical(name) when is_binary(name), do: Map.get(@legacy, name, name)
  def canonical(other), do: other

  @doc "Canonical names for a stored list, de-duplicated, order kept."
  def canonicalize(names) when is_list(names), do: names |> Enum.map(&canonical/1) |> Enum.uniq()
  def canonicalize(other), do: other

  @doc "Every name a stored record may use for `event`: itself and its legacy aliases."
  def names_for(event) when is_binary(event) do
    event = canonical(event)
    [event | for({legacy, ^event} <- @legacy, do: legacy)]
  end

  @doc """
  Announce `event` to webhooks, notification emails and, for a ticket, to
  workflows.

  The context is the one `Escalated.Services.WebhookEvents.dispatch/2` takes
  (`:ticket`, `:reply`, `:tag`, `:agent_id`), plus what
  `Escalated.Notifications` reads: `:actor_id` and `:from` (status changes),
  `:breach_type` (SLA breaches), and `:notify` / `:author` (replies).
  """
  def emit(event, context) when is_binary(event) and is_map(context) do
    WebhookEvents.dispatch(event, context)
    Notifications.notify(event, context)

    case Map.get(context, :ticket) do
      %Ticket{} = ticket -> WorkflowRunner.run_guarded(event, ticket)
      _ -> :ok
    end

    :ok
  end
end
