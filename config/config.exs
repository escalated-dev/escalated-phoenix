import Config

if Mix.env() == :test do
  config :escalated, ecto_repos: [Escalated.TestRepo]

  config :escalated, Escalated.TestRepo,
    database: Path.expand("../tmp/test.db", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    priv: "priv/repo"

  # A second database, standing in for a host that keeps its users somewhere
  # other than Escalated's tables. Deliberately absent from :ecto_repos -- it
  # is not Escalated's to create or migrate, and Escalated's migrations must
  # never run against it.
  config :escalated, Escalated.HostTestRepo,
    database: Path.expand("../tmp/host_test.db", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox

  # :user_repo is deliberately left unset here -- the default (it falls back to
  # :repo) is what every existing test runs against, which is the compatibility
  # claim worth keeping under test. connection_test.exs sets it per case.
  config :escalated,
    repo: Escalated.TestRepo
end
