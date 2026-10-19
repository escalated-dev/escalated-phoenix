defmodule Escalated.WidgetOriginsTest do
  use Escalated.DataCase, async: false

  alias Escalated.Services.SettingsService
  alias Escalated.WidgetOrigins

  setup do
    previous = Application.fetch_env(:escalated, :widget_allowed_origins)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :widget_allowed_origins, value)
        :error -> Application.delete_env(:escalated, :widget_allowed_origins)
      end
    end)

    :ok
  end

  test "normalises admin-entered origins and rejects anything that is not a bare origin" do
    for {entry, expected} <- [
          {"https://Shop.Example.com", "https://shop.example.com"},
          {"https://shop.example.com/", "https://shop.example.com"},
          {"https://shop.example.com:443", "https://shop.example.com"},
          {"http://localhost:5173", "http://localhost:5173"},
          {"https://*.example.com", "https://*.example.com"},
          {"https://*.example.com:8443", "https://*.example.com:8443"},
          {"https://shop.example.com/checkout", nil},
          {"https://shop.example.com?x=1", nil},
          {"shop.example.com", nil},
          {"*", nil},
          {"https://*", nil},
          {"https://a.*.example.com", nil},
          {"ftp://shop.example.com", nil},
          {"https://user@shop.example.com", nil}
        ] do
      assert WidgetOrigins.normalize_pattern(entry) == expected, "entry #{inspect(entry)}"
    end
  end

  test "matches exact origins, ports and subdomain wildcards" do
    Application.put_env(:escalated, :widget_allowed_origins, [
      "https://shop.example.com",
      "https://*.brand.test",
      "http://localhost:5173"
    ])

    for {origin, allowed} <- [
          {"https://shop.example.com", true},
          {"https://SHOP.example.com:443", true},
          {"http://shop.example.com", false},
          {"https://shop.example.com:8443", false},
          {"https://help.brand.test", true},
          {"https://a.b.brand.test", true},
          {"https://brand.test", false},
          {"https://notbrand.test", false},
          {"https://help.brand.test.evil.com", false},
          {"http://localhost:5173", true},
          {"http://localhost", false},
          {"null", false}
        ] do
      assert WidgetOrigins.allows?(origin) == allowed, "origin #{inspect(origin)}"
    end
  end

  test "accepts the config list as a comma separated string" do
    Application.put_env(
      :escalated,
      :widget_allowed_origins,
      "https://shop.example.com, https://*.brand.test"
    )

    assert WidgetOrigins.configured() == ["https://shop.example.com", "https://*.brand.test"]
  end

  test "merges the config list with the admin setting" do
    Application.put_env(:escalated, :widget_allowed_origins, ["https://shop.example.com"])

    {:ok, _} =
      SettingsService.set(
        "widget_allowed_origins",
        "https://blog.example.com, https://bad.example.com/path\n"
      )

    assert WidgetOrigins.configured() == ["https://shop.example.com", "https://blog.example.com"]
    assert WidgetOrigins.allows?("https://blog.example.com")
    refute WidgetOrigins.allows_configured?("https://blog.example.com")
  end

  test "only reports an Origin that names another site" do
    for {origin, expected} <- [
          {nil, nil},
          {"null", nil},
          {"https://help.example.com", nil},
          {"https://help.example.com:443", nil},
          {"https://shop.example.com", "https://shop.example.com"},
          {"http://help.example.com", "http://help.example.com"}
        ] do
      conn = Plug.Test.conn(:get, "https://help.example.com/support/widget/config")

      conn =
        if origin, do: Plug.Conn.put_req_header(conn, "origin", origin), else: conn

      assert WidgetOrigins.cross_origin(conn) == expected, "origin #{inspect(origin)}"
    end
  end
end
