ExUnit.start()

# Eagerly load every module in the package so `function_exported?/3` interface
# assertions are deterministic regardless of test order — module code loads
# lazily otherwise, which made several pre-existing surface tests flaky once the
# suite became runnable.
Application.load(:escalated)

case :application.get_key(:escalated, :modules) do
  {:ok, modules} -> Enum.each(modules, &Code.ensure_loaded/1)
  _ -> :ok
end

{:ok, _} = Application.ensure_all_started(:ecto_sql)

unless Process.whereis(Escalated.TestRepo) do
  {:ok, _} = Escalated.TestRepo.start_link()
  Ecto.Adapters.SQL.Sandbox.mode(Escalated.TestRepo, :manual)
  {:ok, _} = Escalated.Test.FakeProjectStore.start_link([])
end
