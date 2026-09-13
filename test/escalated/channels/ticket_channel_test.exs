defmodule Escalated.Channels.TicketChannelTest do
  @moduledoc """
  Who may join `"escalated:ticket:<id>"`.

  The topic carries every event for one ticket -- status changes, replies,
  assignment -- so the moduledoc promises the requester or an agent. The join
  accepted any signed-in user, so a customer could listen to anyone's ticket
  by changing the id in the topic.
  """
  use Escalated.DataCase, async: false

  alias Escalated.Channels.TicketChannel
  alias Escalated.Services.TicketService

  @requester %{id: 101}
  @stranger %{id: 202}
  @agent %{id: 900, is_agent: true}

  setup do
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
    on_exit(fn -> Application.delete_env(:escalated, :agent_check) end)

    {:ok, ticket} =
      TicketService.create(%{
        subject: "Invoice question",
        description: "Body",
        requester_id: @requester.id,
        requester_type: "user"
      })

    %{topic: "escalated:ticket:#{ticket.id}"}
  end

  defp join(topic, user) do
    TicketChannel.join(topic, %{}, %Phoenix.Socket{assigns: %{current_user: user}})
  end

  test "a signed-in user who is neither the requester nor an agent is refused", %{topic: topic} do
    assert {:error, %{reason: "unauthorized"}} = join(topic, @stranger)
  end

  test "the requester can join", %{topic: topic} do
    assert {:ok, _socket} = join(topic, @requester)
  end

  test "an agent can join", %{topic: topic} do
    assert {:ok, _socket} = join(topic, @agent)
  end

  test "nobody signed in is refused", %{topic: topic} do
    assert {:error, _reason} = join(topic, nil)
  end

  test "a topic naming no ticket is refused to a non-agent" do
    assert {:error, _reason} = join("escalated:ticket:999999", @stranger)
    assert {:error, _reason} = join("escalated:ticket:not-a-number", @stranger)
  end
end
