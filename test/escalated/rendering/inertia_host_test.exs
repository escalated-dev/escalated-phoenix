defmodule Escalated.Rendering.InertiaHostTest do
  use Escalated.DataCase, async: false

  alias Escalated.Test.InertiaHost.Router

  @component "Escalated/Customer/Index"
  @payload ~s(<!--<script></script><script>window.fixtureInjection=true</script>"&')

  setup do
    original = Application.fetch_env(:inertia, :csp_nonce_assign_key)
    Application.put_env(:inertia, :csp_nonce_assign_key, :fixture_csp_nonce)

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:inertia, :csp_nonce_assign_key, value)
        :error -> Application.delete_env(:inertia, :csp_nonce_assign_key)
      end
    end)

    :ok
  end

  test "a normal browser request renders the host layout and bootstraps complete page data" do
    rendered = request(:get, "/fixture/page?" <> URI.encode_query(%{payload: @payload}))

    assert rendered.status == 200
    assert content_type(rendered) =~ "text/html"
    assert rendered.resp_body =~ ~s(id="host-shell")
    refute rendered.resp_body =~ "<script>window.fixtureInjection"
    refute rendered.resp_body =~ "<!--<script>"

    page = initial_page(rendered.resp_body)
    assert page["component"] == @component
    assert page["props"]["payload"] == @payload
    assert page["props"]["title"] == "Fixture page"
    assert page["props"]["auth"]["user"]["id"] == 42
    assert is_map(page["props"]["escalated"])
    assert is_binary(page["version"])
  end

  test "XHR and initial HTML expose the same component and shared props" do
    html = request(:get, "/fixture/page") |> Map.fetch!(:resp_body) |> initial_page()
    rendered = request(:get, "/fixture/page", inertia_headers())
    xhr = Jason.decode!(rendered.resp_body)

    assert rendered.status == 200
    assert content_type(rendered) =~ "application/json"
    assert Plug.Conn.get_resp_header(rendered, "x-inertia") == ["true"]

    assert Enum.any?(
             Plug.Conn.get_resp_header(rendered, "vary"),
             &String.contains?(&1, "X-Inertia")
           )

    assert xhr["component"] == html["component"]
    assert xhr["props"] == html["props"]
    assert xhr["version"] == html["version"]
  end

  test "the negotiated URL retains its encoded query string" do
    path = "/fixture/page?payload=quoted%26value"
    page = request(:get, path, inertia_headers()) |> Map.fetch!(:resp_body) |> Jason.decode!()
    assert page["url"] == path
    assert page["props"]["payload"] == "quoted&value"
  end

  test "session flash is delivered at the adapter's documented boundary" do
    session = %{"phoenix_flash" => %{"plain_text_token" => "synthetic-one-time-token"}}

    for headers <- [[], inertia_headers()] do
      rendered = request(:get, "/fixture/page", headers, session)

      page =
        if headers == [],
          do: initial_page(rendered.resp_body),
          else: Jason.decode!(rendered.resp_body)

      if inertia_three?() do
        assert page["flash"] == %{"plain_text_token" => "synthetic-one-time-token"}
        refute Map.has_key?(page["props"], "flash")
      else
        assert page["props"]["flash"] == %{"plain_text_token" => "synthetic-one-time-token"}
      end

      assert Plug.Conn.get_session(rendered, "phoenix_flash") == nil
    end
  end

  test "script-based bootstrap data receives the configured CSP nonce" do
    rendered = request(:get, "/fixture/page")

    if inertia_three?() do
      assert rendered.resp_body =~ ~r/<script[^>]*nonce="fixture-nonce"[^>]*>/
      assert rendered.resp_body =~ ~r/<script[^>]*type="application\/json"[^>]*>/
    else
      assert rendered.resp_body =~ ~r/<div[^>]*data-page="/
      refute rendered.resp_body =~ ~r/<script[^>]*data-page=/
    end
  end

  test "a stale client version receives the adapter's refresh response" do
    headers = [{"x-inertia", "true"}, {"x-inertia-version", "stale-fixture-version"}]
    rendered = request(:get, "/fixture/page?payload=keep", headers)

    assert rendered.status == 409
    assert [location] = Plug.Conn.get_resp_header(rendered, "x-inertia-location")
    assert location =~ "/fixture/page?payload=keep"
  end

  test "an Inertia PUT redirect uses 303 and keeps flash for the following visit" do
    initial = request(:get, "/fixture/page")
    token = initial.resp_cookies["XSRF-TOKEN"].value
    headers = [{"x-csrf-token", token} | inertia_headers()]
    redirected = request(:put, "/fixture/redirect", headers, Plug.Conn.get_session(initial))
    assert redirected.status == 303
    assert Plug.Conn.get_resp_header(redirected, "location") == ["/fixture/page"]
    assert Plug.Conn.get_session(redirected, "phoenix_flash") == %{"notice" => "Fixture saved"}
  end

  test "an unconfigured Axios CSRF header is rejected by the Phoenix browser pipeline" do
    initial = request(:get, "/fixture/page")
    token = initial.resp_cookies["XSRF-TOKEN"].value
    headers = [{"x-xsrf-token", token} | inertia_headers()]

    error =
      assert_raise Plug.Conn.WrapperError, fn ->
        request(:put, "/fixture/redirect", headers, Plug.Conn.get_session(initial))
      end

    assert %Plug.CSRFProtection.InvalidCSRFTokenError{} = error.reason
  end

  defp request(method, path, headers \\ [], session \\ %{}) do
    conn =
      Plug.Test.conn(method, path)
      |> Plug.Test.init_test_session(session)
      |> Plug.Conn.put_req_header("accept", "text/html")

    conn =
      Enum.reduce(headers, conn, fn {key, value}, conn ->
        Plug.Conn.put_req_header(conn, key, value)
      end)

    Router.call(conn, Router.init([]))
  end

  defp inertia_headers do
    conn =
      Plug.Test.conn(:get, "/fixture/page")
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()
      |> Inertia.Plug.call(Inertia.Plug.init([]))

    [{"x-inertia", "true"}, {"x-inertia-version", to_string(conn.private.inertia_version)}]
  end

  defp inertia_three? do
    :inertia |> Application.spec(:vsn) |> to_string() |> Version.match?("~> 3.0")
  end

  defp content_type(conn), do: conn |> Plug.Conn.get_resp_header("content-type") |> hd()

  defp initial_page(html) do
    if inertia_three?() do
      [_, payload] = Regex.run(~r/<script\b[^>]*\bdata-page="app"[^>]*>(.*?)<\/script>/s, html)
      Jason.decode!(payload)
    else
      [_, payload] = Regex.run(~r/\bdata-page="([^"]*)"/, html)

      payload
      |> String.replace("&quot;", "\"")
      |> String.replace("&#39;", "'")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&amp;", "&")
      |> Jason.decode!()
    end
  end
end
