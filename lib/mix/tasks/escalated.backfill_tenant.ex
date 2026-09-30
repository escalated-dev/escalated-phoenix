defmodule Mix.Tasks.Escalated.BackfillTenant do
  @moduledoc "Preview a legacy tenant backfill; use --apply --writers-stopped after stopping every writer."
  @shortdoc "Assign a legacy installation to one explicitly named, empty tenant"
  use Mix.Task

  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [tenant: :string, apply: :boolean, writers_stopped: :boolean]
      )

    if rest != [] or invalid != [] or is_nil(opts[:tenant]),
      do: Mix.raise("Use --tenant ID [--apply --writers-stopped]")

    Mix.Task.run("app.start")

    result =
      if opts[:apply],
        do:
          Escalated.Tenancy.Backfill.apply(opts[:tenant], writers_stopped: opts[:writers_stopped]),
        else: Escalated.Tenancy.Backfill.preview(opts[:tenant])

    Mix.shell().info(inspect(result, limit: :infinity))

    case result do
      {:error, _} -> Mix.raise("Tenant backfill refused; no rows moved")
      _ -> :ok
    end
  end
end
