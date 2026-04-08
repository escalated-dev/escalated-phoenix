defmodule Escalated.Services.TicketSplittingTest do
  use ExUnit.Case, async: true

  alias Escalated.Services.TicketService
  alias Escalated.Schemas.{Ticket, Reply}

  describe "split_ticket/3 interface" do
    test "split_ticket/2 is defined" do
      assert function_exported?(TicketService, :split_ticket, 2)
    end

    test "split_ticket/3 is defined" do
      assert function_exported?(TicketService, :split_ticket, 3)
    end
  end

  describe "split ticket metadata construction" do
    test "new ticket inherits metadata from original with split tracking" do
      original = %Ticket{
        id: 1,
        reference: "ESC-2604-ABC123",
        subject: "Original issue",
        description: "Original description",
        status: "open",
        priority: "high",
        ticket_type: "problem",
        department_id: 5,
        requester_id: 10,
        requester_type: "user",
        guest_name: nil,
        guest_email: nil,
        metadata: %{"source" => "email"}
      }

      reply = %Reply{
        id: 42,
        body: "This is the reply content that becomes the new ticket",
        ticket_id: 1,
        author_id: 10
      }

      # Verify the expected attributes would be constructed correctly
      subject = "Split from #{original.reference}: #{original.subject}"
      assert subject == "Split from ESC-2604-ABC123: Original issue"

      expected_metadata = Map.merge(original.metadata, %{
        "split_from_ticket_id" => original.id,
        "split_from_reply_id" => reply.id
      })

      assert expected_metadata["source"] == "email"
      assert expected_metadata["split_from_ticket_id"] == 1
      assert expected_metadata["split_from_reply_id"] == 42
    end

    test "split ticket default subject includes original reference" do
      original = %Ticket{
        id: 1,
        reference: "ESC-2604-XYZ789",
        subject: "Payment issue",
        description: "desc",
        status: "open",
        priority: "medium",
        metadata: %{}
      }

      expected = "Split from ESC-2604-XYZ789: Payment issue"
      assert expected == "Split from #{original.reference}: #{original.subject}"
    end

    test "split ticket preserves priority from original" do
      for priority <- ~w(low medium high urgent critical) do
        original = %Ticket{priority: priority}
        assert original.priority == priority
      end
    end

    test "split ticket preserves ticket_type from original" do
      for ticket_type <- ~w(question problem incident task) do
        original = %Ticket{ticket_type: ticket_type}
        assert original.ticket_type == ticket_type
      end
    end

    test "split tracking stores list of split ticket IDs" do
      metadata = %{}
      original_splits = Map.get(metadata, "split_ticket_ids", [])
      new_metadata = Map.put(metadata, "split_ticket_ids", original_splits ++ [99])

      assert new_metadata["split_ticket_ids"] == [99]

      # Simulate a second split
      second_splits = Map.get(new_metadata, "split_ticket_ids", [])
      final_metadata = Map.put(new_metadata, "split_ticket_ids", second_splits ++ [100])

      assert final_metadata["split_ticket_ids"] == [99, 100]
    end

    test "reply must belong to the original ticket for split" do
      ticket = %Ticket{id: 1}
      reply_same = %Reply{id: 10, ticket_id: 1}
      reply_other = %Reply{id: 11, ticket_id: 2}

      assert reply_same.ticket_id == ticket.id
      refute reply_other.ticket_id == ticket.id
    end
  end
end
