defmodule Escalated.Services.TicketActionRegistry do
  @moduledoc """
  Resolves host-defined custom ticket actions.

  Host applications register actions under the `:custom_actions` application
  config key as a list of maps. Each visible action renders as a button on the
  agent ticket screen; triggering it records an internal note and broadcasts the
  `ticket:custom_action_triggered` event.

  Action map shape (all but `:key`/`:label` optional):

      %{
        key: "sync-crm",
        label: "Sync CRM",
        variant: "primary",
        visible: true,                       # boolean or fn(ticket, user) -> boolean
        enabled: true,                       # boolean or fn(ticket, user) -> boolean
        confirmation: "Are you sure?",       # string/nil or fn
        metadata: %{icon: "refresh-cw"}      # map or fn
      }

  Mirrors the Laravel TicketActionRegistry / NestJS reference.
  """

  @doc "All registered actions (with key + label), from application config."
  def all do
    case Escalated.config(:custom_actions, []) do
      actions when is_list(actions) ->
        Enum.filter(actions, fn a -> a[:key] && a[:label] end)

      _ ->
        []
    end
  end

  @doc "Find a single action by key, or nil."
  def find(key) do
    Enum.find(all(), fn a -> to_string(a[:key]) == to_string(key) end)
  end

  def visible?(action, ticket, user) do
    truthy?(resolve(Map.get(action, :visible, true), ticket, user))
  end

  def enabled?(action, ticket, user) do
    truthy?(resolve(Map.get(action, :enabled, true), ticket, user))
  end

  def metadata(action, ticket, user) do
    case resolve(Map.get(action, :metadata, %{}), ticket, user) do
      %{} = m -> m
      _ -> %{}
    end
  end

  @doc """
  The visible actions for a ticket/user, serialized for the UI. The controller
  adds the `url` and `method` before sending to the client.
  """
  def for_ticket(ticket, user) do
    all()
    |> Enum.filter(&visible?(&1, ticket, user))
    |> Enum.map(fn action ->
      confirmation = resolve(Map.get(action, :confirmation), ticket, user)

      %{
        key: to_string(action[:key]),
        label: to_string(resolve(action[:label], ticket, user)),
        variant: to_string(Map.get(action, :variant, "secondary")),
        confirmation: confirmation && to_string(confirmation),
        disabled: not enabled?(action, ticket, user),
        metadata: metadata(action, ticket, user)
      }
    end)
  end

  defp resolve(value, ticket, user) do
    if is_function(value, 2), do: value.(ticket, user), else: value
  end

  defp truthy?(value), do: value != nil and value != false
end
