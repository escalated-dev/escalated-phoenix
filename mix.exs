defmodule Escalated.MixProject do
  use Mix.Project

  @version "0.2.6"
  @source_url "https://github.com/escalated-dev/escalated-phoenix"

  def project do
    [
      app: :escalated,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      mod: {Escalated.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:ecto_sql, "~> 3.14"},
      # Earlier Ecto lines require Decimal 1/2, which have no fix for
      # CVE-2026-97853. Export the patched floor to host applications too.
      {:decimal, ">= 3.1.2 and < 4.0.0"},
      {:jason, "~> 1.4"},
      {:inertia, "~> 2.6", optional: true},
      {:plug, "~> 1.14"},
      {:gettext, "~> 1.0"},
      # IANA time zone data for business hours (schedules keep wall-clock
      # hours in their own zone). Passed explicitly, never installed as the
      # host's global time zone database.
      {:tz, "~> 0.28"},

      # Translations are vendored at priv/gettext/{locale}/LC_MESSAGES/escalated.po
      # from escalated-dev/escalated-locale. Once that Hex package is actually
      # published (publish.yml needs HEX_API_KEY configured), re-add:
      #   {:escalated_locale, "~> 0.1"}
      # and drop the vendored .po files.

      # Dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      # All three only in :test. The suite runs on whichever ESCALATED_TEST_ADAPTER
      # selects; a host app depends on the one adapter it actually uses.
      {:ecto_sqlite3, "~> 0.15", only: :test},
      {:postgrex, "~> 0.17", only: :test},
      {:myxql, "~> 0.6", only: :test},
      # Notification emails go out through the host's Swoosh mailer when one is
      # configured. Escalated builds the %Swoosh.Email{} at runtime, so Swoosh is
      # only needed here to test that path, never forced on a host.
      {:swoosh, "~> 1.16", only: :test}
    ]
  end

  defp aliases do
    [
      # Dropped first, so the run starts from an empty schema whatever the
      # adapter. An in-memory SQLite file is replaced anyway; a PostgreSQL or
      # MySQL database outlives the run, and a half-migrated one from a previous
      # attempt fails in ways that say nothing about the code.
      test: ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  defp description do
    "Embeddable helpdesk and support ticket system for Phoenix applications."
  end

  defp package do
    [
      name: "escalated_phoenix",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv docs .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: [
        "README.md",
        "docs/merchant-and-guest-access.md",
        "docs/embedding-the-widget.md",
        "docs/api-tokens.md"
      ]
    ]
  end
end
