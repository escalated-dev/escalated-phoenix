defmodule Escalated.Serializers.TicketSerializer do
  @moduledoc """
  Shared helpers for computing derived ticket fields expected by the frontend.

  The six computed properties are:
    * `requester_name`  — guest name, or the requester user's `name`
    * `requester_email` — guest email, or the requester user's `email`
    * `last_reply_at`   — ISO-8601 timestamp of the most recent reply
    * `last_reply_author` — name of the most recent reply's author
    * `is_live_chat`    — true when status is "live" and channel is "chat"
    * `is_snoozed`      — true when `snoozed_until` is set and in the future
  """

  alias Escalated.Schemas.Reply
  import Ecto.Query

  @doc """
  Returns a map of the six computed fields for the given ticket.

  The ticket must already have its `replies` association loaded (or an empty
  list will be assumed). If `replies` is not preloaded, the function falls
  back to a single query for the latest reply.
  """
  def computed_fields(ticket) do
    repo = Escalated.repo()
    {requester_name, requester_email} = resolve_requester(ticket, repo)
    {last_reply_at, last_reply_author} = resolve_last_reply(ticket, repo)

    %{
      requester_name: requester_name,
      requester_email: requester_email,
      last_reply_at: last_reply_at,
      last_reply_author: last_reply_author,
      is_live_chat: ticket.status == "live" && ticket.channel == "chat",
      is_snoozed: not is_nil(ticket.snoozed_until) && DateTime.compare(ticket.snoozed_until, DateTime.utc_now()) == :gt
    }
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp resolve_requester(ticket, repo) do
    cond do
      # Guest tickets store name/email directly
      ticket.guest_name != nil || ticket.guest_email != nil ->
        {ticket.guest_name, ticket.guest_email}

      # Registered requester — look up via configured user schema
      ticket.requester_id != nil ->
        user_schema = Escalated.user_schema()

        case repo.get(user_schema, ticket.requester_id) do
          nil ->
            {nil, nil}

          user ->
            name = if function_exported?(user.__struct__, :name, 1), do: user.__struct__.name(user), else: Map.get(user, :name)
            email = Map.get(user, :email)
            {name, email}
        end

      true ->
        {nil, nil}
    end
  end

  defp resolve_last_reply(ticket, repo) do
    last_reply =
      from(r in Reply,
        where: r.ticket_id == ^ticket.id,
        order_by: [desc: r.inserted_at],
        limit: 1
      )
      |> repo.one()

    case last_reply do
      nil ->
        {nil, nil}

      reply ->
        at = reply.inserted_at && DateTime.to_iso8601(reply.inserted_at)
        author = resolve_author_name(reply.author_id, repo)
        {at, author}
    end
  end

  defp resolve_author_name(nil, _repo), do: nil

  defp resolve_author_name(author_id, repo) do
    user_schema = Escalated.user_schema()

    case repo.get(user_schema, author_id) do
      nil -> nil
      user ->
        if function_exported?(user.__struct__, :name, 1), do: user.__struct__.name(user), else: Map.get(user, :name)
    end
  end
end
