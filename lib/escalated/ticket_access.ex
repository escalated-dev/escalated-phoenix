defmodule Escalated.TicketAccess do
  @moduledoc """
  Requester identity checks shared by customer ticket operations.
  """

  alias Escalated.Schemas.Ticket

  def user_id(user) when is_map(user) do
    case Map.get(user, :id, Map.get(user, "id")) do
      id when is_integer(id) -> id
      id when is_binary(id) and id != "" -> id
      _ -> nil
    end
  end

  def user_id(_), do: nil

  def requester?(%Ticket{requester_id: requester_id}, user) when not is_nil(requester_id) do
    case user_id(user) do
      nil -> false
      id -> to_string(requester_id) == to_string(id)
    end
  end

  def requester?(_, _), do: false
end
