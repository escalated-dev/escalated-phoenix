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

# A second, genuinely separate database standing in for the host's own. It is
# not in :ecto_repos, so the `mix test` alias neither creates nor migrates it --
# Escalated's migrations must never run here. The host owns this schema, so the
# table is created by hand, the way a host app's own migrations would.
unless Process.whereis(Escalated.HostTestRepo) do
  _ =
    Escalated.HostTestRepo.__adapter__().storage_up(
      Application.get_env(:escalated, Escalated.HostTestRepo)
    )

  {:ok, _} = Escalated.HostTestRepo.start_link()

  # Still in the sandbox's default :auto mode, so this runs without the
  # wrapping transaction a checkout would roll back.
  Ecto.Adapters.SQL.query!(
    Escalated.HostTestRepo,
    """
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      email TEXT,
      is_admin INTEGER DEFAULT 0,
      is_agent INTEGER DEFAULT 0
    )
    """,
    []
  )

  Ecto.Adapters.SQL.Sandbox.mode(Escalated.HostTestRepo, :manual)
end
