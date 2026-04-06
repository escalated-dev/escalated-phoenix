defmodule Escalated.MixProject do
  use Mix.Project

  @version "0.1.0"
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
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:ecto_sql, "~> 3.10"},
      {:jason, "~> 1.4"},
      {:inertia_phoenix, "~> 0.9", optional: true},
      {:plug, "~> 1.14"},

      # Dev/test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:ecto_sqlite3, "~> 0.15", only: :test}
    ]
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
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
      files: ~w(lib priv .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end
end
