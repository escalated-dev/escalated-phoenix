defmodule Escalated.Schemas.SavedViewTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.SavedView

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          name: "My Open Tickets",
          user_id: 1
        })

      assert changeset.valid?
    end

    test "valid changeset with all fields" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          name: "High Priority",
          user_id: 1,
          filters: %{"priority" => "high", "status" => "open"},
          is_shared: true,
          position: 3
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :filters) == %{"priority" => "high", "status" => "open"}
      assert Ecto.Changeset.get_field(changeset, :is_shared) == true
      assert Ecto.Changeset.get_field(changeset, :position) == 3
    end

    test "invalid without name" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          user_id: 1
        })

      refute changeset.valid?
      assert {:name, _} = hd(changeset.errors)
    end

    test "invalid without user_id" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          name: "My View"
        })

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :user_id)
    end

    test "validates name length max 100" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          name: String.duplicate("a", 101),
          user_id: 1
        })

      refute changeset.valid?
    end

    test "defaults is_shared to false" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          name: "Test",
          user_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :is_shared) == false
    end

    test "defaults position to 0" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          name: "Test",
          user_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :position) == 0
    end

    test "defaults filters to empty map" do
      changeset =
        SavedView.changeset(%SavedView{}, %{
          name: "Test",
          user_id: 1
        })

      assert Ecto.Changeset.get_field(changeset, :filters) == %{}
    end
  end

  describe "service interface" do
    alias Escalated.Services.SavedViewService

    test "create/1 is defined" do
      assert function_exported?(SavedViewService, :create, 1)
    end

    test "update/2 is defined" do
      assert function_exported?(SavedViewService, :update, 2)
    end

    test "update/3 is defined" do
      assert function_exported?(SavedViewService, :update, 3)
    end

    test "delete/1 is defined" do
      assert function_exported?(SavedViewService, :delete, 1)
    end

    test "delete/2 is defined" do
      assert function_exported?(SavedViewService, :delete, 2)
    end

    test "list_for_user/1 is defined" do
      assert function_exported?(SavedViewService, :list_for_user, 1)
    end

    test "find/1 is defined" do
      assert function_exported?(SavedViewService, :find, 1)
    end

    test "reorder/1 is defined" do
      assert function_exported?(SavedViewService, :reorder, 1)
    end
  end
end
