defmodule Escalated.GettextTest do
  # The central escalated-locale catalogues are vendored under priv/gettext so
  # the Hex package carries its own translations. These assert they load with
  # no :escalated_locale dependency, which Hex could not resolve today.
  use ExUnit.Case, async: true

  @locales ~w(ar de en es fr it ja ko nl pl pt_BR ru tr zh_CN)

  test "does not depend on the unpublished escalated_locale package" do
    deps = Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0))
    refute :escalated_locale in deps
    refute Code.ensure_loaded?(EscalatedLocale)
  end

  test "every declared locale has a vendored catalogue" do
    priv = :code.priv_dir(:escalated) |> to_string()

    for locale <- @locales do
      assert File.regular?(Path.join([priv, "gettext", locale, "LC_MESSAGES", "escalated.po"])),
             "missing vendored catalogue for #{locale}"
    end

    assert Enum.sort(Gettext.known_locales(Escalated.Gettext)) == Enum.sort(@locales)
  end

  test "translates from the vendored catalogues" do
    assert translate("en", "nav.admin") == "Admin"
    assert translate("de", "nav.admin") == "Verwaltung"
    assert translate("fr", "nav.dashboard") == "Tableau de bord"
  end

  defp translate(locale, msgid) do
    Gettext.with_locale(Escalated.Gettext, locale, fn ->
      Gettext.dgettext(Escalated.Gettext, "escalated", msgid)
    end)
  end
end
