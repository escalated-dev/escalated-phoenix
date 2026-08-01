defmodule Escalated.Schemas.CannedResponseTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.CannedResponse

  describe "changeset" do
    test "casts allowed fields and validates required title + body" do
      cs =
        CannedResponse.changeset(%CannedResponse{}, %{
          title: "Refund acknowledged",
          body: "Thanks for reaching out — your refund is on its way.",
          category: "Billing",
          is_shared: true,
          created_by: 42
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :title) == "Refund acknowledged"
      assert Ecto.Changeset.get_field(cs, :category) == "Billing"
      assert Ecto.Changeset.get_field(cs, :is_shared) == true
      assert Ecto.Changeset.get_field(cs, :created_by) == 42
    end

    test "defaults is_shared to true" do
      cs = CannedResponse.changeset(%CannedResponse{}, %{title: "Hi", body: "Hello"})
      assert Ecto.Changeset.get_field(cs, :is_shared) == true
    end

    test "rejects when title is missing" do
      cs = CannedResponse.changeset(%CannedResponse{}, %{body: "no title"})
      refute cs.valid?
      assert %{title: _} = errors_on(cs)
    end

    test "rejects when body is missing" do
      cs = CannedResponse.changeset(%CannedResponse{}, %{title: "no body"})
      refute cs.valid?
      assert %{body: _} = errors_on(cs)
    end

    test "rejects a title over 255 chars" do
      cs =
        CannedResponse.changeset(%CannedResponse{}, %{
          title: String.duplicate("a", 256),
          body: "b"
        })

      refute cs.valid?
      assert %{title: _} = errors_on(cs)
    end

    test "rejects a category over 100 chars" do
      cs =
        CannedResponse.changeset(%CannedResponse{}, %{
          title: "t",
          body: "b",
          category: String.duplicate("c", 101)
        })

      refute cs.valid?
      assert %{category: _} = errors_on(cs)
    end
  end

  describe "shared/1 query" do
    test "filters to shared rows" do
      ecto_str = inspect(CannedResponse.shared())
      assert ecto_str =~ "is_shared == true"
    end
  end

  describe "for_agent/2 query" do
    test "filters to shared responses plus the agent's own" do
      ecto_str = inspect(CannedResponse |> CannedResponse.for_agent(42))
      assert ecto_str =~ "is_shared == true"
      assert ecto_str =~ "created_by == ^42"
    end
  end

  describe "to_json/1" do
    test "shapes the row for the agent / admin frontend" do
      json =
        CannedResponse.to_json(%CannedResponse{
          id: 7,
          title: "Refund acknowledged",
          body: "Thanks!",
          category: "Billing",
          is_shared: true,
          created_by: 42
        })

      assert json.id == 7
      assert json.title == "Refund acknowledged"
      assert json.body == "Thanks!"
      assert json.category == "Billing"
      assert json.is_shared == true
      assert json.created_by == 42
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
