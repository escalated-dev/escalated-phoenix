defmodule Mix.Tasks.Escalated.TwoFactor.Reset do
  @shortdoc "Removes a user's two-factor enrolment (lost device)"
  @moduledoc """
  Removes a user's two-factor enrolment so they can set it up again, for a
  lost or replaced device.

      mix escalated.two_factor.reset you@example.com
      mix escalated.two_factor.reset 42 --tenant merchant-id

  The user is found by email, then by ID, in the host's user schema. While
  two-factor is required, they are sent to enrol on their next visit.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    Escalated.Tenancy.Maintenance.run(args, fn remaining ->
      case remaining do
        [user] -> reset(user)
        _ -> Mix.raise("Usage: mix escalated.two_factor.reset USER [--tenant ID]")
      end
    end)
  end

  defp reset(identifier) do
    case Escalated.Roles.find_user(identifier) do
      nil ->
        Mix.raise("No user found for [#{identifier}].")

      user ->
        case Escalated.Services.TwoFactorService.remove(Map.get(user, :id)) do
          0 -> Mix.shell().info("#{identifier} had no two-factor enrolment.")
          _ -> Mix.shell().info("Removed the two-factor enrolment for #{identifier}.")
        end
    end
  end
end
