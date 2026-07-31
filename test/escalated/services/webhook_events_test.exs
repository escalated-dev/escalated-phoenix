defmodule Escalated.Services.WebhookEventsTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.{Reply, Tag, Ticket}
  alias Escalated.Services.WebhookEvents

  describe "build_payload/1" do
    test "ticket-only context emits the full ticket snapshot" do
      ticket = %Ticket{
        id: 1,
        reference: "ESC-1",
        subject: "Help",
        status: "open",
        priority: "high"
      }

      assert WebhookEvents.build_payload(%{ticket: ticket}) == %{
               ticket: %{
                 id: 1,
                 reference: "ESC-1",
                 subject: "Help",
                 status: "open",
                 priority: "high"
               }
             }
    end

    test "reply context trims the ticket to id + reference and adds the reply" do
      ticket = %Ticket{id: 1, reference: "ESC-1", subject: "Help", status: "open"}
      reply = %Reply{id: 7, is_internal: true}

      assert WebhookEvents.build_payload(%{ticket: ticket, reply: reply}) == %{
               ticket: %{id: 1, reference: "ESC-1"},
               reply: %{id: 7, is_internal_note: true}
             }
    end

    test "includes tag and agent_id when present" do
      ticket = %Ticket{id: 1, reference: "ESC-1", subject: "s", status: "open", priority: "low"}
      tag = %Tag{id: 3, name: "vip"}

      payload = WebhookEvents.build_payload(%{ticket: ticket, tag: tag, agent_id: 42})

      assert payload.tag == %{id: 3, name: "vip"}
      assert payload.agent_id == 42
    end

    test "empty context yields an empty payload" do
      assert WebhookEvents.build_payload(%{}) == %{}
    end
  end
end
