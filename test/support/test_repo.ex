defmodule Escalated.TestRepo do
  @moduledoc false

  # The adapter is compile-time, so it is read here rather than from runtime
  # config. Switching ESCALATED_TEST_ADAPTER needs a recompile; each CI leg
  # starts from a clean _build, and locally `mix clean` is the whole story.
  #
  # An unrecognised value raises rather than falling back: a CI leg that quietly
  # ran SQLite would report green having tested nothing the matrix exists for.
  @adapter (case System.get_env("ESCALATED_TEST_ADAPTER", "sqlite") do
              "sqlite" ->
                Ecto.Adapters.SQLite3

              "postgres" ->
                Ecto.Adapters.Postgres

              "mysql" ->
                Ecto.Adapters.MyXQL

              other ->
                raise "ESCALATED_TEST_ADAPTER must be sqlite, postgres or mysql; got #{inspect(other)}."
            end)

  use Ecto.Repo,
    otp_app: :escalated,
    adapter: @adapter
end
