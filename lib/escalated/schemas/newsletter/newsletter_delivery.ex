defmodule Escalated.Schemas.Newsletter.NewsletterDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending queued sent bounced complained suppressed failed)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}newsletter_deliveries" do
    field :newsletter_id, :integer
    field :contact_id, :integer
    field :email_at_send, :string
    field :status, :string, default: "pending"
    field :tracking_token, :string
    field :sent_at, :utc_datetime
    field :opened_at, :utc_datetime
    field :last_clicked_at, :utc_datetime
    field :clicks_count, :integer, default: 0
    field :bounce_reason, :string
    field :failure_reason, :string
    field :attempt_count, :integer, default: 0
    field :claimed_at, :utc_datetime
    field :next_attempt_at, :utc_datetime
    field :is_test, :boolean, default: false
    field :created_at, :utc_datetime
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :newsletter_id,
      :contact_id,
      :email_at_send,
      :status,
      :tracking_token,
      :sent_at,
      :opened_at,
      :last_clicked_at,
      :clicks_count,
      :bounce_reason,
      :failure_reason,
      :attempt_count,
      :claimed_at,
      :next_attempt_at,
      :is_test,
      :created_at
    ])
    |> validate_required([:newsletter_id, :contact_id, :email_at_send, :tracking_token])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:tracking_token)
  end
end
