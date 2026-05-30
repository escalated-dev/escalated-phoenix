ExUnit.start()

{:ok, _} = Application.ensure_all_started(:ecto_sql)

unless Process.whereis(Escalated.TestRepo) do
  {:ok, _} = Escalated.TestRepo.start_link()
  Ecto.Adapters.SQL.Sandbox.mode(Escalated.TestRepo, :manual)
  {:ok, _} = Escalated.Test.FakeProjectStore.start_link([])
end
