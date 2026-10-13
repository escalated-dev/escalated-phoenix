# MIX_ENV=test mix run --no-start scripts/verify_ticket_access_migration.exs
defmodule TicketAccessMigrationProbe do
  alias Ecto.Adapters.SQL

  def run do
    Logger.configure(level: :warning)
    Application.load(:escalated)
    adapter = Escalated.TestRepo.__adapter__()
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    for dependency <- [:ecto_sqlite3, :postgrex, :myxql],
        do: Application.ensure_all_started(dependency)

    name = "phoenix_access_probe_#{System.system_time(:millisecond)}"
    database = if adapter == Ecto.Adapters.SQLite3, do: Path.expand("tmp/#{name}.db"), else: name

    config =
      Application.get_env(:escalated, Escalated.TestRepo)
      |> Keyword.put(:database, database)
      |> Keyword.put(:pool, DBConnection.ConnectionPool)

    Module.create(
      TicketAccessMigrationProbe.Repo,
      quote(do: use(Ecto.Repo, otp_app: :ticket_access_probe, adapter: unquote(adapter))),
      Macro.Env.location(__ENV__)
    )

    repo = TicketAccessMigrationProbe.Repo
    Application.put_env(:ticket_access_probe, repo, config)
    :ok = adapter.storage_up(config)
    {:ok, pid} = repo.start_link()

    try do
      for prefix <- ["escalated_", "Support_"] do
        verify(repo, prefix)
      end
    after
      GenServer.stop(pid)
      # Only the fresh target created above belongs to this probe.
      :ok = adapter.storage_down(config)
    end

    IO.puts(
      "Ticket access migration: populated upgrade/rollback and exact account identity passed for both prefixes"
    )
  end

  defp verify(repo, prefix) do
    Application.put_env(:escalated, :table_prefix, prefix)
    Application.put_env(:escalated, :user_key_type, :string)

    Module.create(
      TicketAccessMigrationProbe.Legacy,
      quote do
        use Ecto.Migration

        def change do
          create table(unquote(prefix <> "departments")) do
            add :name, :string
          end

          create table(unquote(prefix <> "tickets")) do
            add :subject, :string
          end

          create table(unquote(prefix <> "sla_policies")) do
            add :name, :string
          end
        end
      end,
      Macro.Env.location(__ENV__)
    )

    :ok = Ecto.Migrator.up(repo, 1, TicketAccessMigrationProbe.Legacy, log: false)
    repo.insert_all(prefix <> "tickets", [%{subject: "Legacy row"}])
    Code.compile_file("priv/repo/migrations/20261013000001_add_ticket_access.exs")
    migration = Escalated.Repo.Migrations.AddTicketAccess
    :ok = Ecto.Migrator.up(repo, 2, migration, log: false)
    tickets = quote_name(repo, prefix <> "tickets")

    [["Legacy row", nil, nil]] =
      SQL.query!(repo, "SELECT subject, account_type, account_id FROM #{tickets}").rows

    SQL.query!(repo, "UPDATE #{tickets} SET account_type = 'Company', account_id = 'A'")
    [[0]] = SQL.query!(repo, "SELECT COUNT(*) FROM #{tickets} WHERE account_id = 'a'").rows
    :ok = Ecto.Migrator.down(repo, 2, migration, log: false)
    [["Legacy row"]] = SQL.query!(repo, "SELECT subject FROM #{tickets}").rows
    :ok = Ecto.Migrator.down(repo, 1, TicketAccessMigrationProbe.Legacy, log: false)
  end

  defp quote_name(repo, name) do
    quote = if repo.__adapter__() == Ecto.Adapters.MyXQL, do: "`", else: "\""
    quote <> name <> quote
  end
end

TicketAccessMigrationProbe.run()
