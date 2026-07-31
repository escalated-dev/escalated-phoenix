defmodule Escalated.Schemas.WebhookDelivery do
  @moduledoc """
  Ecto schema for a single outbound webhook delivery attempt.

  One row is written per POST attempt (mirroring the Laravel
  `WebhookDelivery` model): the request `event`/`payload`, the observed
  `response_code`/`response_body`, the `attempts` counter and the
  `delivered_at` timestamp once a response is received.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}webhook_deliveries" do
    field :event, :string
    field :payload, :map
    field :response_code, :integer
    field :response_body, :string
    field :attempts, :integer, default: 0
    field :delivered_at, :utc_datetime

    belongs_to :webhook, Escalated.Schemas.Webhook

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :webhook_id,
      :event,
      :payload,
      :response_code,
      :response_body,
      :attempts,
      :delivered_at
    ])
    |> validate_required([:webhook_id, :event])
  end

  @doc "Latest deliveries for a webhook, newest first."
  def for_webhook(query \\ __MODULE__, webhook_id) do
    from(d in query, where: d.webhook_id == ^webhook_id, order_by: [desc: d.id])
  end

  @doc "True when the recorded response was a 2xx."
  def success?(%__MODULE__{response_code: code}) when is_integer(code) do
    code >= 200 and code < 300
  end

  def success?(_), do: false

  @doc "Serialize a delivery row for the admin frontend."
  def to_json(%__MODULE__{} = d) do
    %{
      id: d.id,
      webhook_id: d.webhook_id,
      event: d.event,
      payload: d.payload,
      response_code: d.response_code,
      response_body: d.response_body,
      attempts: d.attempts,
      success: success?(d),
      delivered_at: d.delivered_at,
      inserted_at: d.inserted_at,
      updated_at: d.updated_at
    }
  end
end
