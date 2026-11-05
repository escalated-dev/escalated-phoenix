defmodule Escalated.Embed.ConfigTest do
  @moduledoc """
  `config :escalated, :ui, embed: [...]` (ADR 2026-11-05-embeddable-admin):
  the defaults, and the string forms environment variables arrive in.
  """
  use ExUnit.Case, async: false

  alias Escalated.Embed

  setup do
    on_exit(fn -> Application.delete_env(:escalated, :ui) end)
    Application.delete_env(:escalated, :ui)
    :ok
  end

  defp put(embed), do: Application.put_env(:escalated, :ui, embed: embed)

  test "everything is off by default" do
    refute Embed.enabled?()
    assert Embed.mode() == :layout
    assert Embed.prefix() == "admin/support"
    assert Embed.base_url() == "/admin/support"
    refute Embed.replaces_admin_gate?()
    assert Embed.layout() == nil
    assert Embed.root_view() == nil
    assert Embed.frame_ancestors() == []

    assert Embed.defaults() == [
             enabled: false,
             mode: :layout,
             prefix: "admin/support",
             middleware: nil,
             replace_admin_gate: false,
             layout: nil,
             root_view: nil,
             frame_ancestors: []
           ]
  end

  test "reads the keys, including the string forms of ESCALATED_EMBED* values" do
    put(
      enabled: "true",
      mode: "IFRAME",
      prefix: "/console/support/",
      replace_admin_gate: true,
      layout: "Layouts/ConsoleLayout",
      root_view: {MyHost.Layouts, :admin},
      frame_ancestors: "https://a.example,https://b.example"
    )

    assert Embed.enabled?()
    assert Embed.mode() == :iframe
    assert Embed.prefix() == "console/support"
    assert Embed.base_url() == "/console/support"
    assert Embed.admin_base() == "/console/support"
    assert Embed.admin_path("/tags") == "/console/support/tags"
    assert Embed.replaces_admin_gate?()
    assert Embed.layout() == "Layouts/ConsoleLayout"
    assert Embed.root_view() == {MyHost.Layouts, :admin}
    assert Embed.frame_ancestors() == ["https://a.example", "https://b.example"]
  end

  test "accepts a map" do
    Application.put_env(:escalated, :ui, %{embed: %{enabled: true, prefix: "staff/help"}})
    assert Embed.enabled?()
    assert Embed.base_url() == "/staff/help"
  end

  test "an unknown mode is layout mode; a blank prefix is the default" do
    put(enabled: true, mode: "popup", prefix: " / ")
    assert Embed.mode() == :layout
    assert Embed.prefix() == "admin/support"
  end

  test "keeps exact http(s) origins only" do
    put(
      frame_ancestors: [
        "https://Admin.Example.com",
        "http://localhost:4000",
        "https://admin.example.com/",
        "*",
        "https://*.example.com",
        "https://example.com/admin",
        "https://user:pass@example.com",
        "https://example.com?x=1",
        "javascript:alert(1)",
        "example.com",
        ""
      ]
    )

    assert Embed.frame_ancestors() == ["https://admin.example.com", "http://localhost:4000"]

    assert Embed.frame_ancestors_directive() ==
             "frame-ancestors 'self' https://admin.example.com http://localhost:4000"
  end

  test "an embedded false means the standalone admin" do
    put(enabled: "false", prefix: "console")
    refute Embed.enabled?()
    assert Embed.admin_base() == "/support/admin"
  end
end
