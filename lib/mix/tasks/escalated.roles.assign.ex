defmodule Mix.Tasks.Escalated.Roles.Assign do
  @shortdoc "Gives a user an Escalated role"
  @moduledoc """
  Gives a user an Escalated role, so an install can bootstrap its first admin
  before turning roles & permissions on (`ESCALATED_ROLES_PERMISSIONS`).

      mix escalated.roles.assign you@example.com          # the admin role
      mix escalated.roles.assign you@example.com agent
      mix escalated.roles.assign 42 light_agent --tenant merchant-id

  The user is found by email, then by ID, in the host's user schema. The role
  is a slug (`admin`, `agent`, `light_agent` or a custom role); seed the system
  roles first with `mix escalated.seed_permissions`. The user's other roles
  are kept.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    Escalated.Tenancy.Maintenance.run(args, fn remaining ->
      case remaining do
        [user] -> assign(user, "admin")
        [user, role] -> assign(user, role)
        _ -> Mix.raise("Usage: mix escalated.roles.assign USER [ROLE] [--tenant ID]")
      end
    end)
  end

  defp assign(identifier, role) do
    case Escalated.Roles.assign_to(identifier, role) do
      {:ok, _role} ->
        Mix.shell().info("Gave #{identifier} the #{role} role.")

      {:error, :unknown_user} ->
        Mix.raise("No user found for [#{identifier}].")

      {:error, :unknown_role} ->
        Mix.raise("No role [#{role}]. Seed them with: mix escalated.seed_permissions")
    end
  end
end
