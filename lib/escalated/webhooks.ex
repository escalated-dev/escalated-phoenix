defmodule Escalated.Webhooks do
  @moduledoc """
  Context for outbound webhook subscriptions and their delivery log.

  CRUD over `Escalated.Schemas.Webhook`, the `list_active/1` query used by
  `Escalated.Services.WebhookDispatcher` to fan an event out to subscribers,
  and helpers over the `Escalated.Schemas.WebhookDelivery` log.

  Every function takes the repo module explicitly (mirroring
  `Escalated.Services.MacroService`) so the context stays trivially testable.
  """

  import Ecto.Query

  alias Escalated.Schemas.{Webhook, WebhookDelivery}

  @doc "All webhooks, newest first."
  def list(repo) do
    repo.all(from(w in Webhook, order_by: [desc: w.id]))
  end

  @doc "Active webhooks only (used by the dispatcher)."
  def list_active(repo) do
    repo.all(Webhook.active())
  end

  @doc "Active webhooks subscribed to `event`."
  def subscribed_to(repo, event) when is_binary(event) do
    repo
    |> list_active()
    |> Enum.filter(&Webhook.subscribed_to?(&1, event))
  end

  @doc "Fetch a webhook by id (nil when absent)."
  def get(repo, id), do: repo.get(Webhook, id)

  @doc "Create a webhook."
  def create(repo, attrs) do
    %Webhook{}
    |> Webhook.changeset(attrs)
    |> repo.insert()
  end

  @doc "Update a webhook."
  def update(repo, %Webhook{} = webhook, attrs) do
    webhook
    |> Webhook.changeset(attrs)
    |> repo.update()
  end

  @doc "Delete a webhook (cascades its deliveries)."
  def delete(repo, %Webhook{} = webhook), do: repo.delete(webhook)

  @doc """
  Webhooks decorated with delivery stats for the admin index:
  a `delivery_count` and the `latest_delivery` (serialized or nil).
  """
  def list_with_delivery_stats(repo) do
    Enum.map(list(repo), fn webhook ->
      webhook
      |> Webhook.to_json()
      |> Map.put(:delivery_count, delivery_count(repo, webhook.id))
      |> Map.put(:latest_delivery, latest_delivery_json(repo, webhook.id))
    end)
  end

  @doc "Number of delivery attempts recorded for a webhook."
  def delivery_count(repo, webhook_id) do
    repo.one(from(d in WebhookDelivery, where: d.webhook_id == ^webhook_id, select: count(d.id))) ||
      0
  end

  @doc "Most recent deliveries for a webhook, newest first."
  def list_deliveries(repo, webhook_id, max \\ 50) do
    webhook_id
    |> WebhookDelivery.for_webhook()
    |> limit(^max)
    |> repo.all()
  end

  @doc "Fetch a single delivery by id (nil when absent)."
  def get_delivery(repo, id), do: repo.get(WebhookDelivery, id)

  defp latest_delivery_json(repo, webhook_id) do
    query = webhook_id |> WebhookDelivery.for_webhook() |> limit(1)

    case repo.one(query) do
      nil -> nil
      delivery -> WebhookDelivery.to_json(delivery)
    end
  end
end
