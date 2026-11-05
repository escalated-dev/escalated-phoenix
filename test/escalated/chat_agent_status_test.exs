defmodule Escalated.ChatAgentStatusTest do
  @moduledoc """
  Live chat goes only to agents whose own status is `online`
  (`agent_profiles.chat_status`, ADR 2026-11-05-agent-panel-data), as
  escalated-laravel's chat routing reads it. Away and offline agents, and
  agents with no profile, keep chat unavailable and get no chats.
  """
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{AgentProfile, ChatRoutingRule}
  alias Escalated.Services.{ChatAvailabilityService, ChatRoutingService}
  alias Escalated.Test.Router

  defp repo, do: Escalated.repo()

  defp availability do
    conn =
      conn(:get, "/support/widget/chat/availability")
      |> init_test_session(%{})
      |> put_req_header("accept", "application/json")
      |> Router.call(Router.init([]))

    assert conn.status == 200
    Jason.decode!(conn.resp_body)["data"]["available"]
  end

  setup do
    repo().insert!(
      ChatRoutingRule.changeset(%ChatRoutingRule{}, %{name: "Everyone", agent_ids: [11, 12, 13]})
    )

    repo().insert!(%AgentProfile{user_id: 11, chat_status: "away"})
    repo().insert!(%AgentProfile{user_id: 12, chat_status: "offline"})
    :ok
  end

  test "nobody online: chat is unavailable and routes to nobody" do
    refute ChatAvailabilityService.available?()
    refute availability()
    assert {:ok, nil} = ChatRoutingService.find_available_agent()
  end

  test "an online agent gets the chat and makes chat available" do
    repo().insert!(%AgentProfile{user_id: 13, chat_status: "online"})

    assert ChatAvailabilityService.available?()
    assert availability()
    assert {:ok, 13} = ChatRoutingService.find_available_agent()
  end

  test "online_agents keeps the rule's order and drops everyone else" do
    repo().insert!(%AgentProfile{user_id: 13, chat_status: "online"})
    repo().update_all(AgentProfile, set: [chat_status: "online"])

    assert ChatRoutingService.online_agents([13, 99, 11, 12]) == [13, 11, 12]
    assert ChatRoutingService.online_agents([]) == []
  end
end
