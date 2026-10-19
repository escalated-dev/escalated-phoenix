defmodule Escalated.PackageProbe do
  @moduledoc false

  def run do
    root = Path.expand("..", __DIR__)
    report_dir = Path.join(root, "tmp/package-verification")
    File.mkdir_p!(report_dir)
    report_path = Path.join(report_dir, "report.json")
    File.write!(report_path, Jason.encode!(%{state: "running"}) <> "\n")
    temporary_parent = System.tmp_dir!() |> Path.expand()
    nonce = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    temporary = Path.join(temporary_parent, "escalated-package-#{nonce}")
    File.mkdir!(temporary)

    try do
      package = Path.join(temporary, "package")
      command!(root, ["hex.build", "--unpack", "--output", package], report_dir, "build")

      # This directory is produced by Hex's actual package builder/unpacker,
      # not a copy of the checkout. Published packages intentionally omit locks.
      if File.exists?(Path.join(package, "mix.lock")), do: raise("Unexpected packaged lockfile")
      true = File.regular?(Path.join(package, "lib/escalated/rendering/ui_renderer.ex"))
      # Served at {prefix}/widget/embed.js; the package must ship it.
      true = File.regular?(Path.join(package, "priv/static/widget/escalated-widget.js"))
      # Translations are vendored, not a dependency; the package must carry them.
      true = File.regular?(Path.join(package, "priv/gettext/de/LC_MESSAGES/escalated.po"))
      digest = package_digest(package)
      consumer = write_consumer!(temporary, "consumer", package, "3.1.2")

      command!(consumer, ["deps.get"], report_dir, "consumer-resolve")
      command!(consumer, ["hex.audit"], report_dir, "consumer-audit")
      File.write!(Path.join(consumer, "probe.exs"), consumer_probe())
      command!(consumer, ["run", "probe.exs"], report_dir, "consumer-run")

      rejected = write_consumer!(temporary, "rejected", package, "3.1.1")

      {output, status} =
        command(rejected, ["deps.get"], report_dir, "vulnerable-version-rejection")

      unless status != 0 and String.contains?(output, "version solving failed") and
               String.contains?(output, "decimal") and String.contains?(output, "3.1.2") do
        raise "Expected the packaged dependency requirements to reject vulnerable Decimal 3.1.1"
      end

      unless package_digest(package) == digest,
        do: raise("A consumer changed the unpacked package contents")

      report = %{
        state: "passed",
        elixir: System.version(),
        otp: System.otp_release(),
        package_content_sha256: digest,
        minimum_decimal_consumer: "3.1.2",
        vulnerable_decimal_rejected: "3.1.1",
        optional_inertia_absent: true,
        json_fallback_verified: true
      }

      File.write!(report_path, Jason.encode!(report, pretty: true) <> "\n")

      IO.puts(
        "PACKAGE_PROBE passed: real Hex package, Decimal floor, clean audit, optional UI and JSON fallback"
      )

      IO.puts("PACKAGE_PROBE content SHA256 #{digest}")
    rescue
      error ->
        File.write!(
          report_path,
          Jason.encode!(%{state: "failed", error: Exception.message(error)}) <> "\n"
        )

        reraise error, __STACKTRACE__
    after
      unless Path.dirname(temporary) == temporary_parent and
               String.starts_with?(Path.basename(temporary), "escalated-package-") do
        raise "Refusing to clean an unowned directory"
      end

      File.rm_rf!(temporary)
    end
  end

  defp write_consumer!(temporary, name, package, decimal) do
    consumer = Path.join(temporary, name)
    File.mkdir!(consumer)

    File.write!(Path.join(consumer, "mix.exs"), """
    defmodule PackageConsumer.MixProject do
      use Mix.Project
      def project do
        [app: :package_consumer, version: "0.0.0", elixir: "~> 1.15",
         deps: [{:escalated, path: #{inspect(package)}}, {:decimal, "== #{decimal}"}]]
      end
      def application, do: [extra_applications: [:logger]]
    end
    """)

    consumer
  end

  defp consumer_probe do
    """
    unless to_string(Application.spec(:decimal, :vsn)) == "3.1.2",
      do: raise("The minimum supported Decimal version was not installed")
    if Code.ensure_loaded?(Inertia), do: raise("Optional Inertia was unexpectedly installed")
    conn = Plug.Test.conn(:get, "/package-consumer")
    rendered = Escalated.Rendering.UIRenderer.render_page(conn, "Fixture", %{ok: true})
    unless rendered.status == 200 and Jason.decode!(rendered.resp_body) == %{"ok" => true},
      do: raise("The installed package's JSON fallback failed")
    unless Decimal.to_string(Decimal.round("1.25", 1)) == "1.3",
      do: raise("Decimal precision smoke check failed")
    IO.puts("CONSUMER_PROBE passed: Decimal 3.1.2, no Inertia, rendered JSON")
    """
  end

  defp command!(cwd, args, report_dir, label) do
    {output, status} = command(cwd, args, report_dir, label)
    if status != 0, do: raise("#{label} failed (#{status}):\n#{output}")
    output
  end

  defp command(cwd, args, report_dir, label) do
    {output, status} =
      System.cmd(System.find_executable("mix") || raise("mix is unavailable"), args,
        cd: cwd,
        env: [
          {"MIX_ENV", "prod"},
          {"MIX_BUILD_PATH", Path.join(cwd, "_build")},
          {"MIX_DEPS_PATH", Path.join(cwd, "deps")}
        ],
        stderr_to_stdout: true
      )

    File.write!(Path.join(report_dir, "#{label}.log"), output)
    IO.puts("PACKAGE_PROBE #{label}: exit #{status}")
    {output, status}
  end

  defp package_digest(package) do
    package
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
    |> Enum.map(fn path ->
      [Path.relative_to(path, package), 0, :crypto.hash(:sha256, File.read!(path))]
    end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end

Escalated.PackageProbe.run()
