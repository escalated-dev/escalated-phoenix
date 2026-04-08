defmodule Escalated.BroadcastingTest do
  use ExUnit.Case, async: true

  alias Escalated.Broadcasting
  alias Escalated.Config

  describe "Broadcasting module interface" do
    test "broadcast_ticket_event/2 is defined" do
      assert function_exported?(Broadcasting, :broadcast_ticket_event, 2)
    end

    test "ticket_created/1 is defined" do
      assert function_exported?(Broadcasting, :ticket_created, 1)
    end

    test "ticket_status_changed/3 is defined" do
      assert function_exported?(Broadcasting, :ticket_status_changed, 3)
    end

    test "reply_added/2 is defined" do
      assert function_exported?(Broadcasting, :reply_added, 2)
    end

    test "ticket_assigned/2 is defined" do
      assert function_exported?(Broadcasting, :ticket_assigned, 2)
    end

    test "ticket_priority_changed/3 is defined" do
      assert function_exported?(Broadcasting, :ticket_priority_changed, 3)
    end

    test "subscribe_tickets/0 is defined" do
      assert function_exported?(Broadcasting, :subscribe_tickets, 0)
    end

    test "subscribe_ticket/1 is defined" do
      assert function_exported?(Broadcasting, :subscribe_ticket, 1)
    end

    test "subscribe_agent/1 is defined" do
      assert function_exported?(Broadcasting, :subscribe_agent, 1)
    end

    test "enabled?/0 is defined" do
      assert function_exported?(Broadcasting, :enabled?, 0)
    end

    test "pubsub_server/0 is defined" do
      assert function_exported?(Broadcasting, :pubsub_server, 0)
    end
  end

  describe "enabled?/0" do
    test "returns false when broadcasting_enabled is not configured" do
      # Default config has broadcasting_enabled: false
      refute Broadcasting.enabled?()
    end
  end

  describe "no-op when disabled" do
    test "broadcast_ticket_event returns :ok when disabled" do
      assert Broadcasting.broadcast_ticket_event("test", %{}) == :ok
    end

    test "subscribe_tickets returns :ok when disabled" do
      assert Broadcasting.subscribe_tickets() == :ok
    end

    test "subscribe_ticket returns :ok when disabled" do
      assert Broadcasting.subscribe_ticket(1) == :ok
    end

    test "subscribe_agent returns :ok when disabled" do
      assert Broadcasting.subscribe_agent(1) == :ok
    end
  end

  describe "Config broadcasting_enabled?" do
    test "returns false by default" do
      config = %Config{}
      refute Config.broadcasting_enabled?(config)
    end

    test "returns true when enabled" do
      config = %Config{broadcasting_enabled: true}
      assert Config.broadcasting_enabled?(config)
    end
  end

  describe "TicketChannel module" do
    test "module is defined" do
      assert Code.ensure_loaded?(Escalated.Channels.TicketChannel)
    end

    test "join/3 is defined" do
      assert function_exported?(Escalated.Channels.TicketChannel, :join, 3)
    end

    test "handle_info/2 is defined" do
      assert function_exported?(Escalated.Channels.TicketChannel, :handle_info, 2)
    end
  end
end
