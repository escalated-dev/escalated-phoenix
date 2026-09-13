defmodule Escalated.Schemas.TicketTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.Ticket

  @now ~U[2026-09-13 12:00:00Z]

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
    # The random part was six hex characters, 24 bits a month, and a test here
    # drew 100 references and failed CI when two of them matched. These pin the
    # format and show that every one of the 40 random bits reaches the
    # reference, which proves the size of the space without depending on luck.

    test "keeps the ESC-YYMM- prefix and adds 8 characters of Crockford base32" do
      assert Ticket.generate_reference() =~ ~r/\AESC-\d{4}-[0-9A-HJKMNP-TV-Z]{8}\z/
    end

    test "stamps the year and month and encodes the random bytes" do
      assert Ticket.generate_reference(@now, <<0::40>>) == "ESC-2609-00000000"
      assert Ticket.generate_reference(@now, <<0xFFFFFFFFFF::40>>) == "ESC-2609-ZZZZZZZZ"
    end

    test "maps each 5-bit group to its own character, so all 40 bits count" do
      alphabet = String.graphemes("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

      # 32 distinct characters per position, none of them easy to misread.
      assert length(Enum.uniq(alphabet)) == 32
      refute Enum.any?(~w(I L O U), &(&1 in alphabet))

      for position <- 0..7, {char, value} <- Enum.with_index(alphabet) do
        random = <<0::size(position * 5), value::5, 0::size((7 - position) * 5)>>
        suffix = String.duplicate("0", position) <> char <> String.duplicate("0", 7 - position)

        assert Ticket.generate_reference(@now, random) == "ESC-2609-" <> suffix
      end
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
      assert length(statuses) == 10
      assert "live" in statuses
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
