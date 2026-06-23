defmodule Mix.Tasks.Escalated.SeedPermissions do
  @shortdoc "Seeds Escalated permission rows (including newsletter slugs)"
  @moduledoc false
  use Mix.Task

  alias Escalated.Permissions.Catalog
  alias Escalated.Schemas.Permission

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")
    repo = Escalated.repo()

    Enum.each(Catalog.all(), fn attrs ->
      case repo.get_by(Permission, slug: attrs.slug) do
        nil ->
          %Permission{}
          |> Permission.changeset(attrs)
          |> repo.insert!()

        row ->
          row |> Permission.changeset(attrs) |> repo.update!()
      end
    end)

    Mix.shell().info("Escalated: seeded #{length(Catalog.all())} permission(s).")
  end
end
