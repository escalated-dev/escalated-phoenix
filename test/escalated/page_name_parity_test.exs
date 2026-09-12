defmodule Escalated.PageNameParityTest do
  use ExUnit.Case, async: true

  # Every page name this package renders has to resolve to a component in
  # @escalated-dev/escalated.
  #
  # Inertia resolving a name to nothing is not an error. The response is a 200,
  # the resolver returns undefined, Vue renders nothing, and the panel comes up
  # blank -- which reads as a permissions problem or an empty dataset. Four
  # screens shipped that way across this portfolio before anyone noticed.
  #
  # Neither repo's tests can see it alone: a controller test asserts a status,
  # and the frontend never hears the name. This is the comparison, against the
  # manifest the frontend package publishes and this repo vendors at
  # test/fixtures/escalated-pages.json.
  #
  # Adding a screen goes: component into the frontend, frontend release,
  # refresh the fixture, then render the name here. In that order, or it ships
  # blank.

  @manifest Path.join(__DIR__, "../fixtures/escalated-pages.json")

  # Names that render a blank panel today and are not fixed by renaming.
  #
  # Settings/Index has no component because this package's settings surface is
  # a different set of fields from the shared Settings screen: it exposes
  # route_prefix, table_prefix, ui_enabled, api_enabled, sla and
  # notification_channels, while the component is built around
  # guest_tickets_enabled, ticket_reference_prefix, max_attachments_per_reply
  # and the inbound-email adapters. Pointing the name at the shared component
  # would render a form of undefined values whose Save posts fields update/2
  # ignores -- worse than blank, because it looks like it works. Closing it is
  # a settings-parity job, not a rename.
  #
  # This list may shrink. It must never grow.
  @known_blank ["Escalated/Admin/Settings/Index"]

  @page_name ~r/"(Escalated\/[A-Za-z0-9\/_]+)"/

  test "renders only page names the frontend ships" do
    rendered = rendered_pages()

    assert map_size(rendered) > 0,
           "found no page names at all, which means this test is not looking where it should"

    missing =
      rendered
      |> Map.keys()
      |> Enum.reject(&(&1 in shipped_pages() or &1 in @known_blank))
      |> Enum.sort()

    assert missing == [], explain(missing, rendered)
  end

  test "the manifest is present and looks like one" do
    # A fixture gone missing or empty would make the test above pass by
    # comparing against nothing.
    assert File.exists?(@manifest)
    assert length(shipped_pages()) > 50
    assert Enum.all?(shipped_pages(), &String.starts_with?(&1, "Escalated/"))
  end

  test "does not keep excusing names that have been fixed" do
    # The exception list is a record of work still owed. Leaving an entry in it
    # after the screen is fixed is how the list stops meaning anything.
    rendered = rendered_pages()

    stale =
      Enum.reject(@known_blank, fn name ->
        Map.has_key?(rendered, name) and name not in shipped_pages()
      end)

    assert stale == [],
           "these names are on the blank-screen exception list but no longer need to be, " <>
             "remove them:\n  " <> Enum.join(stale, "\n  ")
  end

  defp shipped_pages do
    @manifest |> File.read!() |> Jason.decode!() |> Map.fetch!("pages")
  end

  # Page names rendered anywhere in lib/, mapped to the files that render them,
  # so a failure can name the file and not only the string.
  defp rendered_pages do
    root = Path.expand(Path.join(__DIR__, "../../lib"))

    Path.wildcard(Path.join(root, "**/*.ex"))
    |> Enum.reduce(%{}, fn path, acc ->
      file = Path.relative_to(path, root)

      @page_name
      |> Regex.scan(File.read!(path), capture: :all_but_first)
      |> List.flatten()
      |> Enum.reduce(acc, fn name, acc ->
        Map.update(acc, name, MapSet.new([file]), &MapSet.put(&1, file))
      end)
    end)
  end

  defp explain(missing, rendered) do
    body =
      Enum.map_join(missing, "\n", fn name ->
        "  #{name}  (#{rendered |> Map.fetch!(name) |> Enum.join(", ")})"
      end)

    """
    these page names have no component in @escalated-dev/escalated, so they render a blank panel:
    #{body}

    Either the name is wrong, or the component has not been released yet.
    If it has been: refresh test/fixtures/escalated-pages.json from the package.
    """
  end
end
