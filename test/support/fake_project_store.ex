defmodule Escalated.Test.FakeProjectStore do
  @moduledoc false
  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def reset!, do: Agent.update(__MODULE__, fn _ -> %{} end)

  def put(project) do
    Agent.update(__MODULE__, fn state -> Map.put(state, project.id, project) end)
    project
  end

  def get(id), do: Agent.get(__MODULE__, &Map.get(&1, id))
end
