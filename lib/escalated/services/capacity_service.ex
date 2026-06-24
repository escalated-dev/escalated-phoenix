defmodule Escalated.Services.CapacityService do
  @moduledoc """
  Per-agent concurrent-ticket capacity tracking. Mirrors the Laravel
  `CapacityService`: capacities are lazily created (default ceiling 10)
  the first time an agent is referenced, then incremented/decremented as
  tickets are assigned and resolved.
  """
  import Ecto.Query

  alias Escalated.Schemas.AgentCapacity

  @doc "Whether the agent can accept another ticket on the channel."
  @spec can_accept_ticket?(integer() | String.t(), String.t()) :: boolean()
  def can_accept_ticket?(user_id, channel \\ "default") do
    user_id |> first_or_create(channel) |> AgentCapacity.has_capacity?()
  end

  @doc "Increment the agent's current load by one."
  def increment_load(user_id, channel \\ "default") do
    cap = first_or_create(user_id, channel)

    cap
    |> AgentCapacity.changeset(%{current_count: cap.current_count + 1})
    |> Escalated.repo().update()
  end

  @doc "Decrement the agent's current load by one (never below zero)."
  def decrement_load(user_id, channel \\ "default") do
    cap = first_or_create(user_id, channel)

    if cap.current_count > 0 do
      cap
      |> AgentCapacity.changeset(%{current_count: cap.current_count - 1})
      |> Escalated.repo().update()
    else
      {:ok, cap}
    end
  end

  @doc "All capacity rows, ordered by agent, for the admin view."
  def all_capacities do
    Escalated.repo().all(from(c in AgentCapacity, order_by: [asc: c.user_id, asc: c.channel]))
  end

  defp first_or_create(user_id, channel) do
    repo = Escalated.repo()

    case repo.get_by(AgentCapacity, user_id: user_id, channel: channel) do
      nil ->
        {:ok, cap} =
          %AgentCapacity{}
          |> AgentCapacity.changeset(%{user_id: user_id, channel: channel})
          |> repo.insert()

        cap

      cap ->
        cap
    end
  end
end
