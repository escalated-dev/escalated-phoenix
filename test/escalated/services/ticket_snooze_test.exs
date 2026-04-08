defmodule Escalated.Services.TicketSnoozeTest do
  use ExUnit.Case, async: true

  alias Escalated.Services.TicketService
  alias Escalated.Schemas.Ticket

  describe "snooze interface" do
    test "snooze_ticket/2 is defined" do
      assert function_exported?(TicketService, :snooze_ticket, 2)
    end

    test "snooze_ticket/3 is defined" do
      assert function_exported?(TicketService, :snooze_ticket, 3)
    end

    test "unsnooze_ticket/1 is defined" do
      assert function_exported?(TicketService, :unsnooze_ticket, 1)
    end

    test "unsnooze_ticket/2 is defined" do
      assert function_exported?(TicketService, :unsnooze_ticket, 2)
    end

    test "wake_snoozed_tickets/0 is defined" do
      assert function_exported?(TicketService, :wake_snoozed_tickets, 0)
    end
  end

  describe "Ticket schema snooze fields" do
    test "snoozed status is valid" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Test snooze",
          description: "desc",
          status: "snoozed"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "snoozed"
    end

    test "snoozed_until field is castable" do
      until = ~U[2026-04-10 12:00:00Z]

      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Test snooze",
          description: "desc",
          snoozed_until: until
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :snoozed_until) == until
    end

    test "snoozed_by field is castable" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Test snooze",
          description: "desc",
          snoozed_by: 42
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :snoozed_by) == 42
    end

    test "status_before_snooze field is castable" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Test snooze",
          description: "desc",
          status_before_snooze: "in_progress"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status_before_snooze) == "in_progress"
    end
  end

  describe "snoozed?/1" do
    test "returns true for snoozed ticket with snoozed_until" do
      ticket = %Ticket{status: "snoozed", snoozed_until: ~U[2026-04-10 12:00:00Z]}
      assert Ticket.snoozed?(ticket)
    end

    test "returns false for non-snoozed ticket" do
      ticket = %Ticket{status: "open", snoozed_until: nil}
      refute Ticket.snoozed?(ticket)
    end

    test "returns false for snoozed status without snoozed_until" do
      ticket = %Ticket{status: "snoozed", snoozed_until: nil}
      refute Ticket.snoozed?(ticket)
    end
  end

  describe "statuses/0 includes snoozed" do
    test "snoozed is in the statuses list" do
      assert "snoozed" in Ticket.statuses()
    end
  end

  describe "Mix task module" do
    test "Mix.Tasks.Escalated.WakeSnoozedTickets is defined" do
      assert Code.ensure_loaded?(Mix.Tasks.Escalated.WakeSnoozedTickets)
    end

    test "Mix task implements run/1" do
      assert function_exported?(Mix.Tasks.Escalated.WakeSnoozedTickets, :run, 1)
    end
  end
end
