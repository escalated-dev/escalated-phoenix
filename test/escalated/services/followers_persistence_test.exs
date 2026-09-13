defmodule Escalated.Services.FollowersPersistenceTest do
  @moduledoc """
  Following a ticket twice records one follower.

  `add_follower/2` leans on the (ticket_id, user_id) unique index and
  `on_conflict: :nothing`. It named a conflict target, which MySQL cannot
  express, so on MySQL every follow raised instead of inserting.
  """
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.TicketFollower
  alias Escalated.Services.{Followers, TicketService}

  test "following a ticket twice is idempotent" do
    {:ok, ticket} = TicketService.create(%{subject: "Printer", description: "Jammed"})

    assert {:ok, _follower} = Followers.add_follower(ticket.id, 42)
    assert {:ok, _duplicate} = Followers.add_follower(ticket.id, 42)

    assert Followers.follower_user_ids(ticket.id) == ["42"]
    assert Escalated.repo().aggregate(TicketFollower, :count) == 1
  end
end
