defmodule Escalated.Services.ChatAvailabilityService do
  @moduledoc """
  Service for checking live chat availability.

  Determines whether any agents are available to handle new chat sessions,
  and provides queue length information for the widget.
  """

  alias Escalated.Schemas.{ChatRoutingRule, ChatSession}
  alias Escalated.Services.ChatRoutingService
  import Ecto.Query

  @doc """
  Checks whether live chat is currently available.

  Returns `true` if at least one routing rule is active and at least
  one agent in those rules is below their concurrent-chat limit.
  """
  def available? do
    repo = Escalated.repo()

    rules = repo.all(ChatRoutingRule.active())

    Enum.any?(rules, fn rule ->
      is_list(rule.agent_ids) &&
        Enum.any?(rule.agent_ids, fn agent_id ->
          ChatRoutingService.count_active_chats(agent_id) < rule.max_concurrent_chats
        end)
    end)
  end

  @doc """
  Returns the number of visitors currently waiting in the chat queue.
  """
  def queue_length do
    repo = Escalated.repo()

    repo.one(
      from(s in ChatSession,
        where: s.status == "waiting",
        select: count(s.id)
      )
    )
  end

  @doc """
  Returns the full availability status for the widget.
  """
  def get_status do
    %{
      available: available?(),
      queue_length: queue_length()
    }
  end
end
