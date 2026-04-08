defmodule Escalated.Schemas.TicketChatTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.Ticket

  describe "live_chat?/1" do
    test "returns true when channel is chat" do
      ticket = %Ticket{channel: "chat"}
      assert Ticket.live_chat?(ticket)
    end

    test "returns false when channel is not chat" do
      ticket = %Ticket{channel: "email"}
      refute Ticket.live_chat?(ticket)
    end

    test "returns false when channel is nil" do
      ticket = %Ticket{channel: nil}
      refute Ticket.live_chat?(ticket)
    end
  end

  describe "chat_active?/1" do
    test "returns true for active live chat" do
      ticket = %Ticket{channel: "chat", status: "live", chat_ended_at: nil}
      assert Ticket.chat_active?(ticket)
    end

    test "returns false when status is not live" do
      ticket = %Ticket{channel: "chat", status: "open", chat_ended_at: nil}
      refute Ticket.chat_active?(ticket)
    end

    test "returns false when chat has ended" do
      ticket = %Ticket{channel: "chat", status: "live", chat_ended_at: DateTime.utc_now()}
      refute Ticket.chat_active?(ticket)
    end

    test "returns false when channel is not chat" do
      ticket = %Ticket{channel: "email", status: "live", chat_ended_at: nil}
      refute Ticket.chat_active?(ticket)
    end
  end

  describe "changeset with chat fields" do
    test "accepts chat fields" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Test",
          description: "Test desc",
          channel: "chat",
          chat_metadata: %{"started_at" => "2026-04-08T10:00:00Z"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :channel) == "chat"
    end

    test "live status is valid" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Chat",
          description: "Hi",
          status: "live",
          channel: "chat"
        })

      assert changeset.valid?
    end
  end
end
