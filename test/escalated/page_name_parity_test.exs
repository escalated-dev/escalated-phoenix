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

  # Settings now renders the existing shared page with explicit capabilities
  # and persistent consumers. No blank-page exceptions remain.
  @known_blank []

  # Shipped pages no controller renders yet: a ledger of what the shared UI
  # offers that this backend does not serve. It has to match exactly, so a page
  # that starts rendering is taken off it, and a page the frontend adds shows
  # up here as owed rather than going unnoticed. A page whose feature this
  # backend does not have stays on it; see the CHANGELOG for which those are.
  @not_yet_rendered ~w(
    Escalated/Admin/ApiTokens/Index
    Escalated/Admin/BusinessHours/Form
    Escalated/Admin/BusinessHours/Index
    Escalated/Admin/CustomFields/Form
    Escalated/Admin/CustomFields/Index
    Escalated/Admin/CustomObjects/Form
    Escalated/Admin/CustomObjects/Index
    Escalated/Admin/CustomObjects/Records
    Escalated/Admin/Import/Connect
    Escalated/Admin/Import/Index
    Escalated/Admin/Import/Mapping
    Escalated/Admin/Import/Progress
    Escalated/Admin/Import/Review
    Escalated/Admin/Reports/AgentDetail
    Escalated/Admin/Settings/DatabaseConnection
    Escalated/Admin/Settings/EmailSettings
    Escalated/Admin/Settings/PublicTickets
    Escalated/Admin/Settings/Sandbox
    Escalated/Admin/Settings/SsoSettings
    Escalated/Admin/Settings/TwoFactor
    Escalated/Admin/Statuses/Form
    Escalated/Admin/Statuses/Index
    Escalated/Admin/Workflows/Builder
    Escalated/Auth/TwoFactorChallenge
    Escalated/Error
    Escalated/Plugin/Page
  )

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

  test "the not-yet-rendered ledger names exactly the shipped pages nothing renders" do
    rendered = rendered_pages()
    unrendered = shipped_pages() |> Enum.reject(&Map.has_key?(rendered, &1)) |> Enum.sort()

    assert unrendered == Enum.sort(@not_yet_rendered),
           "update @not_yet_rendered.\n  now rendered: " <>
             inspect(@not_yet_rendered -- unrendered) <>
             "\n  not rendered and not listed: " <> inspect(unrendered -- @not_yet_rendered)
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
