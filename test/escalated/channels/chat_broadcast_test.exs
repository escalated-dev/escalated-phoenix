defmodule Escalated.Channels.ChatBroadcastTest do
  @moduledoc """
  Live chat events have to reach the topics `Escalated.Channels.ChatChannel`
  subscribes to: `"escalated:chat:<ticket_id>"` for one session and
  `"escalated:chat:queue"` for the agents' waiting list.

  `ChatSessionService` published every chat event through
  `Broadcasting.broadcast_ticket_event/2`, which only knows the ticket topics.
  A guest or agent joined to a chat channel heard nothing: no messages, no
  agent joining, no session ending.
  """
  use Escalated.DataCase, async: false

  alias Escalated.Services.ChatSessionService

  @pubsub Escalated.Test.ChatBroadcastPubSub

  setup do
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    Application.put_env(:escalated, :broadcasting_enabled, true)
    Application.put_env(:escalated, :pubsub_server, @pubsub)

    on_exit(fn ->
      Application.delete_env(:escalated, :broadcasting_enabled)
      Application.delete_env(:escalated, :pubsub_server)
    end)

    :ok
  end

  defp start_chat! do
    {:ok, ticket, session} =
      ChatSessionService.start_session(%{guest_name: "Visitor", message: "Hi there"})

    {ticket, session}
  end

  defp subscribe(topic), do: :ok = Phoenix.PubSub.subscribe(@pubsub, topic)

  test "a chat message reaches the session's chat topic" do
    {ticket, session} = start_chat!()
    subscribe("escalated:chat:#{ticket.id}")
    # Control: the ticket topic already carried chat events, which proves
    # broadcasting is switched on for this test and the chat topic is the gap.
    subscribe("escalated:ticket:#{ticket.id}")

    {:ok, _reply} = ChatSessionService.send_message(session, "Can you help?")

    assert_receive %{event: "chat:message", payload: %{body: "Can you help?"}}
    assert_receive %{event: "chat:message", payload: %{body: "Can you help?"}}
  end

  test "a new session reaches the agents' queue topic" do
    subscribe("escalated:chat:queue")

    {ticket, _session} = start_chat!()

    ticket_id = ticket.id
    assert_receive %{event: "chat:session_started", payload: %{ticket_id: ^ticket_id}}
  end

  test "an agent joining and the session ending reach the session and the queue" do
    {ticket, session} = start_chat!()
    subscribe("escalated:chat:#{ticket.id}")
    subscribe("escalated:chat:queue")

    {:ok, active} = ChatSessionService.assign_agent(session, 900)
    {:ok, _ended} = ChatSessionService.end_session(active, causer_id: 900)

    for event <- ["chat:agent_joined", "chat:session_ended"] do
      # Once on the session topic, once on the queue.
      assert_receive %{event: ^event}
      assert_receive %{event: ^event}
    end
  end
end
