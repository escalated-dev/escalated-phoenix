defmodule Escalated do
  @moduledoc """
  Escalated — Embeddable helpdesk and support ticket system for Phoenix.

  ## Configuration

      config :escalated,
        repo: MyApp.Repo,
        user_schema: MyApp.Accounts.User,
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
  Returns the configured Ecto repo module.
  """
  def repo do
    config(:repo) || raise "Escalated: :repo must be configured"
  end

  @doc """
  Returns the configured user schema module.
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
