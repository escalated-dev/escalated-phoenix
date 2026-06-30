defmodule Escalated.Services.Followers do
  @moduledoc """
  Ticket followers — host users who follow a ticket and are a notification
  target alongside the assignee and requester.

  The package abstracts the host user table and has no notification fan-out of
  its own, so `follower_recipients/2` resolves the recipient user ids (minus the
  actor, de-duplicated) for the host app to deliver to. See issue #78.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.TicketFollower

  @doc """
  Excludes the actor (a user is never notified of their own action) and
  de-duplicates the given user ids, preserving order. Ids are compared as
  strings so integer and uuid/string host keys both work.
  """
  def follower_recipients(user_ids, exclude_user_id) do
    exclude = exclude_user_id && to_string(exclude_user_id)

    user_ids
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == exclude))
    |> Enum.uniq()
  end

  @doc "Idempotently records a user as following a ticket."
  def add_follower(ticket_id, user_id) do
    attrs = %{ticket_id: ticket_id, user_id: to_string(user_id)}

    %TicketFollower{}
    |> TicketFollower.changeset(attrs)
    |> Escalated.repo().insert(on_conflict: :nothing, conflict_target: [:ticket_id, :user_id])
  end

  @doc "User ids following a ticket, minus the actor and de-duplicated."
  def follower_user_ids(ticket_id, exclude_user_id \\ nil) do
    query = from(f in TicketFollower, where: f.ticket_id == ^ticket_id, select: f.user_id)

    query
    |> Escalated.repo().all()
    |> follower_recipients(exclude_user_id)
  end
end
