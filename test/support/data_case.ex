defmodule Escalated.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using _opts do
    quote do
      setup tags do
        Escalated.DataCase.setup_sandbox(tags)
        :ok
      end
    end
  end

  def setup_sandbox(tags) do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Escalated.TestRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Escalated.TestRepo, {:shared, self()})
    end

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.checkin(Escalated.TestRepo) end)
  end
end
