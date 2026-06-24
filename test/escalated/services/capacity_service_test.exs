defmodule Escalated.Services.CapacityServiceTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.AgentCapacity
  alias Escalated.Services.CapacityService

  defp repo, do: Escalated.repo()

  defp insert_capacity!(attrs) do
    {:ok, cap} =
      %AgentCapacity{}
      |> AgentCapacity.changeset(attrs)
      |> repo().insert()

    cap
  end

  describe "AgentCapacity helpers" do
    test "has_capacity? compares current load to the ceiling" do
      assert AgentCapacity.has_capacity?(%AgentCapacity{current_count: 3, max_concurrent: 10})
      refute AgentCapacity.has_capacity?(%AgentCapacity{current_count: 10, max_concurrent: 10})
    end

    test "load_percentage handles uncapped agents" do
      assert AgentCapacity.load_percentage(%AgentCapacity{current_count: 5, max_concurrent: 0}) ==
               100.0

      assert AgentCapacity.load_percentage(%AgentCapacity{current_count: 5, max_concurrent: 10}) ==
               50.0
    end
  end

  describe "CapacityService" do
    test "lazily creates a capacity row with the default ceiling" do
      assert CapacityService.can_accept_ticket?(1)

      assert [cap] = CapacityService.all_capacities()
      assert cap.user_id == 1
      assert cap.max_concurrent == 10
      assert cap.current_count == 0
    end

    test "increment and decrement track load and never go below zero" do
      {:ok, _} = CapacityService.increment_load(7)
      assert repo().get_by(AgentCapacity, user_id: 7, channel: "default").current_count == 1

      {:ok, _} = CapacityService.decrement_load(7)
      assert repo().get_by(AgentCapacity, user_id: 7, channel: "default").current_count == 0

      {:ok, _} = CapacityService.decrement_load(7)
      assert repo().get_by(AgentCapacity, user_id: 7, channel: "default").current_count == 0
    end

    test "can_accept_ticket? is false once the agent is at capacity" do
      insert_capacity!(%{user_id: 9, channel: "default", max_concurrent: 1, current_count: 1})
      refute CapacityService.can_accept_ticket?(9)
    end

    test "user_id + channel is unique" do
      insert_capacity!(%{user_id: 5, channel: "default"})

      assert {:error, cs} =
               %AgentCapacity{}
               |> AgentCapacity.changeset(%{user_id: 5, channel: "default"})
               |> repo().insert()

      refute cs.valid?
    end
  end

  describe "modules load" do
    test "the capacity controller is compiled" do
      assert Code.ensure_loaded?(Escalated.Controllers.Admin.CapacityController)
    end
  end
end
