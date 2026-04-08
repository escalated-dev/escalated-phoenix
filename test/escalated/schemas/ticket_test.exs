defmodule Escalated.Schemas.TicketTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.Ticket

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Login not working",
          description: "I cannot log in to my account."
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :status) == "open"
      assert Ecto.Changeset.get_field(changeset, :priority) == "medium"
      assert Ecto.Changeset.get_field(changeset, :reference) != nil
    end

    test "invalid without subject" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          description: "Some description"
        })

      refute changeset.valid?
      assert {:subject, _} = hd(changeset.errors)
    end

    test "invalid without description" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Some subject"
        })

      refute changeset.valid?
      assert {:description, _} = hd(changeset.errors)
    end

    test "validates subject length" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: String.duplicate("a", 256),
          description: "desc"
        })

      refute changeset.valid?
    end

    test "validates status inclusion" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Test",
          description: "Test",
          status: "invalid_status"
        })

      refute changeset.valid?
    end

    test "validates priority inclusion" do
      changeset =
        Ticket.changeset(%Ticket{}, %{
          subject: "Test",
          description: "Test",
          priority: "invalid_priority"
        })

      refute changeset.valid?
    end
  end

  describe "generate_reference/0" do
    test "generates a reference with ESC prefix" do
      ref = Ticket.generate_reference()
      assert String.starts_with?(ref, "ESC-")
      assert String.length(ref) > 10
    end

    test "generates unique references" do
      refs = for _ <- 1..100, do: Ticket.generate_reference()
      assert length(Enum.uniq(refs)) == 100
    end
  end

  describe "open?/1" do
    test "returns true for open statuses" do
      for status <- ~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened) do
        assert Ticket.open?(%Ticket{status: status})
      end
    end

    test "returns false for closed statuses" do
      for status <- ~w(resolved closed) do
        refute Ticket.open?(%Ticket{status: status})
      end
    end
  end

  describe "statuses/0" do
    test "returns all valid statuses" do
      statuses = Ticket.statuses()
      assert "open" in statuses
      assert "closed" in statuses
      assert "resolved" in statuses
      assert length(statuses) == 9
    end
  end

  describe "priorities/0" do
    test "returns all valid priorities" do
      priorities = Ticket.priorities()
      assert "low" in priorities
      assert "critical" in priorities
      assert length(priorities) == 5
    end
  end
end
