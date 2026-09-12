defmodule Escalated do
  @moduledoc """
  Escalated — Embeddable helpdesk and support ticket system for Phoenix.

  ## Configuration

      config :escalated,
        repo: MyApp.Repo,
        user_schema: MyApp.Accounts.User,
        # Optional. Only when your users live on a different repo than
        # Escalated's own tables -- see `user_repo/0`.
        user_repo: MyApp.Repo,
        route_prefix: "/support",
        table_prefix: "escalated_",
        ui_enabled: true,
        admin_check: &MyApp.Accounts.admin?/1,
        agent_check: &MyApp.Accounts.agent?/1

  ## Router

  Mount the routes in your Phoenix router:

      use Escalated.Router
      escalated_routes("/support")
  """

  @doc """
  The repo Escalated's own tables live on.

  In Ecto the repo *is* the connection, so pointing `:repo` at a second repo is
  all it takes to keep support tables out of your primary database -- a schema
  shared with a legacy system, a separate reporting store, or a database you
  would simply rather not mix support data into.

  Your users do not move with it. See `user_repo/0`.
  """
  def repo do
    config(:repo) || raise "Escalated: :repo must be configured"
  end

  @doc """
  The repo the host's user schema lives on.

  Defaults to `repo/0`, which is every host that has not split its databases --
  the same module, so nothing about those installs changes.

  Set `:user_repo` when Escalated's tables live somewhere your users do not.
  Escalated stores user ids as plain unconstrained columns precisely so the two
  can be apart: there is no `belongs_to` from an Escalated schema to your user
  schema, and every user lookup is a separate query rather than a join, because
  no database can join across two connections.
  """
  def user_repo do
    config(:user_repo) || repo()
  end

  @doc """
  Returns the configured user schema module.

  Query it through `user_repo/0`, never `repo/0` -- on a split install those are
  different databases, and your users are not in Escalated's.
  """
  def user_schema do
    config(:user_schema) || raise "Escalated: :user_schema must be configured"
  end

  @doc """
  Returns the full table name with the configured prefix.
  """
  def table_name(name) do
    "#{config(:table_prefix, "escalated_")}#{name}"
  end

  @doc """
  Returns a configuration value.
  """
  def config(key, default \\ nil) do
    Application.get_env(:escalated, key, default)
  end

  @doc """
  Returns the full Escalated configuration as a Config struct.
  """
  def configuration do
    Escalated.Config.from_env()
  end
end
