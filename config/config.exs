import Config

if Mix.env() == :test do
  config :escalated, ecto_repos: [Escalated.TestRepo]

  config :escalated, Escalated.TestRepo,
    database: Path.expand("../tmp/test.db", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox

  config :escalated,
    repo: Escalated.TestRepo
end
