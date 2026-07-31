defmodule Escalated.Schemas.Webhook do
  @moduledoc """
  Ecto schema for an outbound webhook subscription.

  A webhook subscribes a remote HTTP endpoint (`url`) to one or more
  Escalated event names (`events`). When a subscribed event fires, an
  `Escalated.Schemas.WebhookDelivery` row records the POST attempt.

  Mirrors the Laravel `Escalated\\Laravel\\Models\\Webhook` contract.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}webhooks" do
    field :url, :string
    # List of subscribed event-name strings, e.g. ["ticket.created"].
    field :events, {:array, :string}, default: []
    # Optional shared secret; when set, deliveries carry an HMAC-SHA256
    # signature header derived from the raw request body.
    field :secret, :string
    field :active, :boolean, default: true

    has_many :deliveries, Escalated.Schemas.WebhookDelivery, foreign_key: :webhook_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:url, :events, :secret, :active])
    |> validate_required([:url])
    |> validate_events()
  end

  # Ecto's validate_required/validate_length both treat `[]` as present, so
  # enforce "at least one event" explicitly to mirror the reference's
  # `events: required|array|min:1`.
  defp validate_events(changeset) do
    case get_field(changeset, :events) || [] do
      [] -> add_error(changeset, :events, "must contain at least one event")
      _ -> changeset
    end
  end

  @doc "Restricts a query to active webhooks, newest first."
  def active(query \\ __MODULE__) do
    from(w in query, where: w.active == true, order_by: [desc: w.id])
  end

  @doc "True when this webhook subscribes to the given event name."
  def subscribed_to?(%__MODULE__{events: events}, event) when is_binary(event) do
    event in (events || [])
  end

  @doc "Serialize a webhook row for the admin frontend."
  def to_json(%__MODULE__{} = w) do
    %{
      id: w.id,
      url: w.url,
      events: w.events || [],
      # Never expose the raw secret; surface only whether one is set.
      has_secret: is_binary(w.secret) and w.secret != "",
      active: w.active,
      inserted_at: w.inserted_at,
      updated_at: w.updated_at
    }
  end
end
