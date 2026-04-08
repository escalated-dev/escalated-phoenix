defmodule Escalated.Schemas.ChatSessionTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.ChatSession

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = ChatSession.changeset(%ChatSession{}, %{ticket_id: 1})
      assert changeset.valid?
    end

    test "invalid without ticket_id" do
      changeset = ChatSession.changeset(%ChatSession{}, %{})
      refute changeset.valid?
      assert {:ticket_id, _} = hd(changeset.errors)
    end

    test "validates status inclusion" do
      changeset = ChatSession.changeset(%ChatSession{}, %{ticket_id: 1, status: "invalid"})
      refute changeset.valid?
    end

    test "accepts valid statuses" do
      for status <- ~w(waiting active ended abandoned) do
        changeset = ChatSession.changeset(%ChatSession{}, %{ticket_id: 1, status: status})
        assert changeset.valid?, "expected #{status} to be valid"
      end
    end
  end

  describe "defaults" do
    test "default status is waiting" do
      session = %ChatSession{}
      assert session.status == "waiting"
    end
  end

  describe "predicates" do
    test "active?/1" do
      assert ChatSession.active?(%ChatSession{status: "active"})
      refute ChatSession.active?(%ChatSession{status: "waiting"})
      refute ChatSession.active?(%ChatSession{status: "ended"})
    end

    test "waiting?/1" do
      assert ChatSession.waiting?(%ChatSession{status: "waiting"})
      refute ChatSession.waiting?(%ChatSession{status: "active"})
    end
  end

  describe "statuses/0" do
    test "returns all valid statuses" do
      statuses = ChatSession.statuses()
      assert "waiting" in statuses
      assert "active" in statuses
      assert "ended" in statuses
      assert "abandoned" in statuses
    end
  end
end
