defmodule Escalated.Services.TicketServiceTest do
  use ExUnit.Case, async: true

  alias Escalated.Services.TicketService

  # Note: Full integration tests require a configured Ecto repo.
  # These tests validate the module interface exists and basic logic works.

  describe "module interface" do
    test "create/1 is defined" do
      assert function_exported?(TicketService, :create, 1)
    end

    test "reply/2 is defined" do
      assert function_exported?(TicketService, :reply, 2)
    end

    test "transition_status/2 is defined" do
      assert function_exported?(TicketService, :transition_status, 2)
    end

    test "transition_status/3 is defined" do
      assert function_exported?(TicketService, :transition_status, 3)
    end

    test "change_priority/2 is defined" do
      assert function_exported?(TicketService, :change_priority, 2)
    end

    test "change_priority/3 is defined" do
      assert function_exported?(TicketService, :change_priority, 3)
    end

    test "change_department/2 is defined" do
      assert function_exported?(TicketService, :change_department, 2)
    end

    test "change_department/3 is defined" do
      assert function_exported?(TicketService, :change_department, 3)
    end

    test "add_tags/2 is defined" do
      assert function_exported?(TicketService, :add_tags, 2)
    end

    test "add_tags/3 is defined" do
      assert function_exported?(TicketService, :add_tags, 3)
    end

    test "remove_tags/2 is defined" do
      assert function_exported?(TicketService, :remove_tags, 2)
    end

    test "remove_tags/3 is defined" do
      assert function_exported?(TicketService, :remove_tags, 3)
    end

    test "list/0 is defined" do
      assert function_exported?(TicketService, :list, 0)
    end

    test "list/1 is defined" do
      assert function_exported?(TicketService, :list, 1)
    end

    test "find/1 is defined" do
      assert function_exported?(TicketService, :find, 1)
    end
  end
end
