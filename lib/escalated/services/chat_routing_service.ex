defmodule Escalated.Services.ChatRoutingService do
  @moduledoc """
  Service for routing incoming chat sessions to available agents.

  Evaluates active routing rules and selects the best agent
  based on the configured strategy (round_robin, least_active).
  """

  alias Escalated.Schemas.{AgentProfile, ChatRoutingRule, ChatSession}
  import Ecto.Query

  # Agent used for round-robin state (stored in process dictionary for simplicity)
  @round_robin_key :escalated_chat_round_robin

  @doc """
  Finds an available agent based on active routing rules.

  Returns `{:ok, agent_id}` or `{:ok, nil}` if no agent is available.
  """
  def find_available_agent(department_id \\ nil, ticket \\ nil) do
    repo = Escalated.repo()

    rules =
      ChatRoutingRule.active()
      |> maybe_filter_department(department_id)
      |> repo.all()

    agent_id =
      Enum.find_value(rules, fn rule ->
        ids =
          (rule.agent_ids || [])
          |> online_agents()
          |> Enum.filter(fn id ->
            not Escalated.TicketVisibility.enabled?() or
              (ticket && Escalated.TicketVisibility.can_assign?(ticket, id))
          end)

        evaluate_rule(%{rule | agent_ids: ids}, repo)
      end)

    {:ok, agent_id}
  end

  @doc """
  The agents among `agent_ids` whose own status (`agent_profiles.chat_status`,
  ADR 2026-11-05-agent-panel-data) is `"online"`, in the given order. Away and
  offline agents, and agents with no profile, get no new chats, as
  escalated-laravel's chat routing.
  """
  def online_agents([]), do: []

  def online_agents(agent_ids) when is_list(agent_ids) do
    online =
      Escalated.repo().all(
        from(p in AgentProfile,
          where: p.user_id in ^agent_ids and p.chat_status == "online",
          select: p.user_id
        )
      )
      |> MapSet.new(&to_string/1)

    Enum.filter(agent_ids, &MapSet.member?(online, to_string(&1)))
  end

  @doc """
  Counts active chat sessions for a given agent.
  """
  def count_active_chats(agent_id) do
    repo = Escalated.repo()

    repo.one(
      from(s in ChatSession,
        where: s.agent_id == ^agent_id and s.status == "active",
        select: count(s.id)
      )
    )
  end

  # Private

  defp evaluate_rule(%{agent_ids: ids} = rule, repo) when is_list(ids) and ids != [] do
    case rule.strategy do
      "least_active" -> least_active(ids, rule.max_concurrent_chats, repo)
      _ -> round_robin(rule, ids, rule.max_concurrent_chats, repo)
    end
  end

  defp evaluate_rule(_, _), do: nil

  defp round_robin(rule, agent_ids, max_chats, repo) do
    index = get_round_robin_index(rule.id)
    n = length(agent_ids)

    result =
      Enum.find_value(0..(n - 1), fn i ->
        agent_id = Enum.at(agent_ids, rem(index + i, n))
        count = active_chat_count(agent_id, repo)

        if count < max_chats do
          put_round_robin_index(rule.id, rem(index + i + 1, n))
          agent_id
        end
      end)

    result
  end

  defp least_active(agent_ids, max_chats, repo) do
    agent_ids
    |> Enum.map(fn id -> {id, active_chat_count(id, repo)} end)
    |> Enum.filter(fn {_id, count} -> count < max_chats end)
    |> Enum.min_by(fn {_id, count} -> count end, fn -> nil end)
    |> case do
      {id, _count} -> id
      nil -> nil
    end
  end

  defp active_chat_count(agent_id, repo) do
    repo.one(
      from(s in ChatSession,
        where: s.agent_id == ^agent_id and s.status == "active",
        select: count(s.id)
      )
    )
  end

  defp maybe_filter_department(query, nil), do: query

  defp maybe_filter_department(query, department_id) do
    from(r in query, where: is_nil(r.department_id) or r.department_id == ^department_id)
  end

  defp get_round_robin_index(rule_id) do
    state = Process.get(@round_robin_key, %{})
    Map.get(state, {Escalated.Tenancy.current_id!(), rule_id}, 0)
  end

  defp put_round_robin_index(rule_id, index) do
    state = Process.get(@round_robin_key, %{})

    Process.put(
      @round_robin_key,
      Map.put(state, {Escalated.Tenancy.current_id!(), rule_id}, index)
    )
  end
end
