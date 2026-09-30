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

  def requester?(%Ticket{requester_id: requester_id} = ticket, user)
      when not is_nil(requester_id) do
    Escalated.Tenancy.assert_record!(ticket)

    case user_id(user) do
      nil ->
        false

      id ->
        Escalated.Tenancy.member?(user) and host_requester?(ticket) and
          to_string(requester_id) == to_string(id)
    end
  rescue
    Escalated.Tenancy.Error -> false
  end

  def requester?(_, _), do: false

  defp host_requester?(ticket) do
    ticket.requester_type in [nil, "user", "User", to_string(Escalated.config(:user_schema))]
  end
end
