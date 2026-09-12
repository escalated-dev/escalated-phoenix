import Config

if Mix.env() == :test do
  # The suite runs on SQLite unless ESCALATED_TEST_ADAPTER says otherwise, so it
  # needs nothing installed locally. CI runs it twice -- sqlite and postgres --
  # because the two disagree about enough to matter: reading a key out of a JSON
  # column is spelled differently, PostgreSQL truncates identifiers at 63 bytes
  # where SQLite keeps them whole, and SQLite accepts DDL and values PostgreSQL
  # rejects outright.
  #
  # "mysql" is accepted here and the code is written for it, but there is no CI
  # leg: the schema uses PostgreSQL array columns in eight places
  # (`{:array, :map}` for workflow actions, `{:array, :string}` for webhook
  # events, and so on) and MySQL has no array type. Supporting it means changing
  # those columns and the schemas over them, not adding a job.
  #
  # An unrecognised value raises rather than falling back: a CI leg that quietly
  # ran SQLite would report green having tested nothing the matrix exists for.
  adapter =
    case System.get_env("ESCALATED_TEST_ADAPTER", "sqlite") do
      "sqlite" ->
        Ecto.Adapters.SQLite3

      "postgres" ->
        Ecto.Adapters.Postgres

      "mysql" ->
        Ecto.Adapters.MyXQL

      other ->
        raise "ESCALATED_TEST_ADAPTER must be sqlite, postgres or mysql; got #{inspect(other)}."
    end

  config :escalated, ecto_repos: [Escalated.TestRepo]

  # The adapter itself is compile-time and lives in Escalated.TestRepo; this is
  # only the connection it should open.
  common = [
    pool: Ecto.Adapters.SQL.Sandbox,
    priv: "priv/repo"
  ]

  postgres? = adapter == Ecto.Adapters.Postgres
  default_user = if postgres?, do: "postgres", else: "root"
  default_port = if postgres?, do: "5432", else: "3306"

  server = [
    hostname: System.get_env("ESCALATED_TEST_HOST", "127.0.0.1"),
    username: System.get_env("ESCALATED_TEST_USERNAME", default_user),
    password: System.get_env("ESCALATED_TEST_PASSWORD", ""),
    port: String.to_integer(System.get_env("ESCALATED_TEST_PORT", default_port))
  ]

  repo_config =
    case adapter do
      Ecto.Adapters.SQLite3 ->
        [database: Path.expand("../tmp/test.db", __DIR__)] ++ common

      _ ->
        [database: System.get_env("ESCALATED_TEST_DATABASE", "escalated_test")] ++
          common ++ server
    end

  config :escalated, Escalated.TestRepo, repo_config

  # A second database, standing in for a host that keeps its users somewhere
  # other than Escalated's tables. Deliberately absent from :ecto_repos -- it
  # is not Escalated's to create or migrate, and Escalated's migrations must
  # never run against it.
  #
  # Pinned to SQLite whatever the adapter: what connection_test.exs proves is
  # that two repos are two databases, which is the same code on every adapter,
  # and two throwaway SQLite files are the only way to get two genuinely empty
  # schemas without a second server.
  config :escalated, Escalated.HostTestRepo,
    database: Path.expand("../tmp/host_test.db", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    adapter: Ecto.Adapters.SQLite3

  # :user_repo is deliberately left unset here -- the default (it falls back to
  # :repo) is what every existing test runs against, which is the compatibility
  # claim worth keeping under test. connection_test.exs sets it per case.
  config :escalated,
    repo: Escalated.TestRepo
end
