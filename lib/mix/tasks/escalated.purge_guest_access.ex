defmodule Mix.Tasks.Escalated.PurgeGuestAccess do
  @moduledoc """
  Deletes expired guest challenges, grants, and global mailbox budgets.

  Schedule `mix escalated.purge_guest_access` hourly. With tenancy enabled, this
  uses the trusted tenant catalog, or `--tenant ID` selects one tenant. Each run
  deletes at most 1,000 expired rows per tenant table, plus 1,000 expired global
  mailbox buckets once. Schedule more frequently for a larger expired backlog.
  Active mailbox budgets and grants are never reset.
  """
  use Mix.Task

  alias Escalated.Services.GuestAccess
  alias Escalated.Tenancy.Maintenance

  @shortdoc "Deletes a bounded batch of expired guest access records"
  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    results =
      Maintenance.run(args, fn
        [] -> GuestAccess.purge_expired()
        _ -> raise ArgumentError, "Only --tenant ID is supported"
      end)

    buckets = GuestAccess.purge_expired_mailboxes()
    challenges = Enum.sum(Enum.map(results, fn {_, counts} -> counts.challenges end))
    grants = Enum.sum(Enum.map(results, fn {_, counts} -> counts.grants end))

    Mix.shell().info(
      "Escalated: purged #{challenges} expired challenge(s), #{grants} grant(s), #{buckets} mailbox bucket(s)."
    )
  end
end
