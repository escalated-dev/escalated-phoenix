defmodule Escalated.Schemas.TicketActivity do
  @moduledoc """
  Ecto schema for ticket activity log entries.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}ticket_activities" do
    field :action, :string
    field :description, :string
    field :causer_id, :integer
    field :details, :map, default: %{}

    belongs_to :ticket, Escalated.Schemas.Ticket

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:action, :description, :causer_id, :details, :ticket_id])
    |> validate_required([:action, :ticket_id])
  end

  def reverse_chronological(query \\ __MODULE__) do
    from(a in query, order_by: [desc: a.inserted_at])
  end
end
