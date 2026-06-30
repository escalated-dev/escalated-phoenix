defmodule Escalated.Schemas.TicketFollower do
  @moduledoc """
  Join row: a host user following a ticket. Followers are a notification
  target alongside the assignee and requester, recorded via the `add_follower`
  workflow action. Unique per `(ticket_id, user_id)`. See issue #78.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}ticket_followers" do
    field :ticket_id, :id
    field :user_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(follower, attrs) do
    follower
    |> cast(attrs, [:ticket_id, :user_id])
    |> validate_required([:ticket_id, :user_id])
  end
end
