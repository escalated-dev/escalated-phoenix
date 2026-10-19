defmodule Escalated.Controllers.WidgetEmbeddingTest do
  @moduledoc """
  Cross-origin embedding of the support widget, through a host router mounted
  the way the README recommends (Escalated.Test.WidgetEmbedRouter): CORS for
  listed sites only, no CSRF token needed from those sites but still required
  from everyone else, embedded visitors always treated as guests, and host
  parameters stored with tickets and chats.
  """
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.SettingsService
  alias Escalated.Test.{GuestAccessHelpers, WidgetEmbedRouter}
  alias Escalated.TestRepo

  @host "https://help.example.com"
  @shop "https://shop.example.com"

  defmodule DenyRateLimit do
    @moduledoc false
    def check(_bucket, _key, _max, _window), do: {:deny, 30_000}
  end

  setup do
    GuestAccessHelpers.configure()
    keys = [:widget_allowed_origins, :widget_settings, :rate_limit_backend]
    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :widget_allowed_origins, [@shop])
    Application.delete_env(:escalated, :widget_settings)
    Application.delete_env(:escalated, :rate_limit_backend)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "answers a preflight from an allowed site" do
    conn =
      request(:options, "/support/widget/tickets", nil,
        origin: @shop,
        headers: [
          {"access-control-request-method", "POST"},
          {"access-control-request-headers", "content-type"}
        ]
      )

    assert conn.status == 204
    assert header(conn, "access-control-allow-origin") == @shop
    assert header(conn, "access-control-allow-methods") == "GET, POST, OPTIONS"

    assert header(conn, "access-control-allow-headers") ==
             "Accept, Authorization, Content-Type, X-Requested-With"

    assert header(conn, "access-control-max-age") == "600"
    assert header(conn, "vary") =~ "Origin"
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end

  test "gives no CORS grant to a site that is not allowed" do
    preflight =
      request(:options, "/support/widget/tickets", nil,
        origin: "https://evil.example.net",
        headers: [{"access-control-request-method", "POST"}]
      )

    assert preflight.status == 204
    assert get_resp_header(preflight, "access-control-allow-origin") == []

    conn = request(:get, "/support/widget/config", nil, origin: "https://evil.example.net")
    assert conn.status == 200
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "lets an allowed site create a ticket without a CSRF token" do
    conn = request(:post, "/support/widget/tickets", ticket_params(), origin: @shop)

    assert conn.status == 201
    assert header(conn, "access-control-allow-origin") == @shop
    assert header(conn, "access-control-expose-headers") == "Retry-After"
    assert get_resp_header(conn, "access-control-allow-credentials") == []
    assert TestRepo.aggregate(Ticket, :count) == 1
  end

  test "still requires a CSRF token from other sites and from the same site" do
    for origin <- [nil, @host, "https://evil.example.net"] do
      assert %Plug.CSRFProtection.InvalidCSRFTokenError{} =
               raised(fn ->
                 request(:post, "/support/widget/tickets", ticket_params(), origin: origin)
               end)
    end

    assert TestRepo.aggregate(Ticket, :count) == 0
  end

  test "reads allowed sites from the admin setting, including subdomain wildcards" do
    Application.put_env(:escalated, :widget_allowed_origins, [])
    {:ok, _} = SettingsService.set("widget_allowed_origins", "https://*.brand.test\n")

    allowed = request(:get, "/support/widget/config", nil, origin: "https://help.brand.test")
    assert header(allowed, "access-control-allow-origin") == "https://help.brand.test"

    apex = request(:get, "/support/widget/config", nil, origin: "https://brand.test")
    assert get_resp_header(apex, "access-control-allow-origin") == []

    conn =
      request(:post, "/support/widget/tickets", ticket_params(), origin: "https://a.brand.test")

    assert conn.status == 201
  end

  test "treats an embedded visitor as a guest even when signed in to the host" do
    user = %{"id" => 7, "is_admin" => true}

    embedded = request(:get, "/support/widget/config", nil, origin: @shop, session: user)
    assert embedded.status == 200
    assert embedded.assigns[:current_user] == nil

    same_site = request(:get, "/support/widget/config", nil, origin: @host, session: user)
    assert same_site.assigns[:current_user] == user
  end

  test "adds CORS headers to error answers for allowed sites" do
    invalid =
      request(:post, "/support/widget/tickets", Map.put(ticket_params(), "metadata", "x"),
        origin: @shop
      )

    assert invalid.status == 422
    assert header(invalid, "access-control-allow-origin") == @shop

    missing = request(:get, "/support/widget/tickets/NOPE", nil, origin: @shop)
    assert missing.status == 404
    assert header(missing, "access-control-allow-origin") == @shop

    Application.put_env(:escalated, :rate_limit_backend, DenyRateLimit)
    limited = request(:get, "/support/widget/config", nil, origin: @shop)
    assert limited.status == 429
    assert header(limited, "access-control-allow-origin") == @shop
    assert header(limited, "access-control-expose-headers") == "Retry-After"
    assert header(limited, "retry-after") == "30"
    assert header(limited, "vary") =~ "Origin"
  end

  test "tells the widget it accepts host parameters" do
    body = request(:get, "/support/widget/config") |> json()

    assert body["accepts_metadata"] == true
    assert body["widget"]["accepts_metadata"] == true
    assert body["guest_verification_required"] == true
  end

  test "stores host parameters sent with a widget ticket" do
    metadata = %{
      "order_id" => " 1234 ",
      "plan" => "pro",
      "seats" => 5,
      "ratio" => 1.5,
      "trial" => false,
      "page_url" => "https://shop.example.com/checkout?step=2",
      "embedded_on" => "https://spoofed.example.org",
      "source" => "spoofed",
      "nested" => %{"a" => 1},
      "list" => [1, 2],
      "empty" => nil,
      "bad key!" => "x",
      String.duplicate("k", 65) => "x",
      "note" => String.duplicate("a", 600)
    }

    conn =
      request(:post, "/support/widget/tickets", Map.put(ticket_params(), "metadata", metadata),
        origin: @shop
      )

    assert conn.status == 201
    ticket = TestRepo.one!(Ticket)

    assert ticket.metadata == %{
             "source" => "widget",
             "order_id" => "1234",
             "plan" => "pro",
             "seats" => 5,
             "ratio" => 1.5,
             "trial" => false,
             "page_url" => "https://shop.example.com/checkout?step=2",
             "embedded_on" => @shop,
             "note" => String.duplicate("a", 500)
           }
  end

  test "drops a page_url that is not a web address and an embedded_on claim" do
    metadata = %{
      "page_url" => "javascript:alert(1)",
      "embedded_on" => "https://spoofed.example.org",
      "plan" => "pro"
    }

    conn =
      request(
        :post,
        "/support/widget/tickets",
        Map.put(ticket_params(), "metadata", metadata),
        Escalated.Test.Router
      )

    assert conn.status == 201
    assert TestRepo.one!(Ticket).metadata == %{"source" => "widget", "plan" => "pro"}
  end

  test "keeps at most 25 entries and rejects more than 50 keys" do
    many = fn n -> Map.new(1..n, &{"key_#{String.pad_leading("#{&1}", 2, "0")}", &1}) end

    conn =
      request(:post, "/support/widget/tickets", Map.put(ticket_params(), "metadata", many.(30)),
        origin: @shop
      )

    assert conn.status == 201
    # 25 host entries plus the server's own source and embedded_on.
    assert map_size(TestRepo.one!(Ticket).metadata) == 27

    too_many =
      request(:post, "/support/widget/tickets", Map.put(ticket_params(), "metadata", many.(51)),
        origin: @shop
      )

    assert too_many.status == 422
    assert json(too_many)["errors"]["metadata"]
    assert TestRepo.aggregate(Ticket, :count) == 1
  end

  test "leaves widget tickets without host parameters unchanged" do
    conn = request(:post, "/support/widget/tickets", ticket_params(), Escalated.Test.Router)

    assert conn.status == 201
    assert TestRepo.one!(Ticket).metadata == %{"source" => "widget"}
  end

  test "lets an allowed site start a live chat and keeps its host parameters" do
    params =
      %{"name" => "Recipient", "message" => "Hello"}
      |> Map.merge(GuestAccessHelpers.proof("recipient@example.test", "chat"))
      |> Map.put("metadata", %{"plan" => "pro", "embedded_on" => "https://spoofed.example.org"})

    conn = request(:post, "/support/widget/chat/start", params, origin: @shop)

    assert conn.status == 201
    assert header(conn, "access-control-allow-origin") == @shop
    ticket = TestRepo.one!(Ticket)
    assert ticket.channel == "chat"
    assert ticket.metadata == %{"plan" => "pro", "embedded_on" => @shop}
  end

  test "serves the standalone widget script for other sites to load" do
    conn = request(:get, "/support/widget/embed.js")

    assert conn.status == 200
    assert header(conn, "content-type") == "application/javascript; charset=utf-8"
    assert header(conn, "cache-control") == "public, max-age=3600"
    assert header(conn, "x-content-type-options") == "nosniff"
    assert header(conn, "cross-origin-resource-policy") == "cross-origin"
    assert header(conn, "access-control-allow-origin") == "*"
    assert conn.resp_body =~ "EscalatedWidget"
    etag = header(conn, "etag")
    assert etag =~ ~r/^"[0-9a-f]{32}"$/

    cached =
      request(:get, "/support/widget/embed.js", nil, headers: [{"if-none-match", etag}])

    assert cached.status == 304
    assert cached.resp_body == ""
    assert header(cached, "etag") == etag

    legacy = request(:get, "/support/widget/embed.js", nil, Escalated.Test.Router)
    assert legacy.status == 200
  end

  test "the package's own router answers preflights and grants CORS without host changes" do
    preflight =
      request(:options, "/support/widget/chat/start", nil, Escalated.Test.Router,
        origin: @shop,
        headers: [{"access-control-request-method", "POST"}]
      )

    assert preflight.status == 204
    assert header(preflight, "access-control-allow-origin") == @shop

    conn = request(:get, "/support/widget/config", nil, Escalated.Test.Router, origin: @shop)
    assert header(conn, "access-control-allow-origin") == @shop
  end

  defp ticket_params do
    Map.merge(
      %{
        "name" => "Recipient",
        "subject" => "Parcel question",
        "description" => "Where is my parcel?"
      },
      GuestAccessHelpers.proof()
    )
  end

  # The router wraps an exception raised in a pipeline with the conn it had.
  defp raised(fun) do
    fun.()
    flunk("expected the request to raise")
  rescue
    error in Plug.Conn.WrapperError -> error.reason
    error -> error
  end

  defp request(method, path, body \\ nil, router \\ WidgetEmbedRouter, opts \\ [])

  defp request(method, path, body, opts, []) when is_list(opts),
    do: request(method, path, body, WidgetEmbedRouter, opts)

  defp request(method, path, body, router, opts) do
    conn =
      conn(method, @host <> path, if(is_nil(body), do: nil, else: Jason.encode!(body)))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> Map.put(:remote_ip, {10, 0, :rand.uniform(250), :rand.uniform(250)})
      |> init_test_session(
        if(opts[:session], do: %{"signed_in_user" => opts[:session]}, else: %{})
      )

    conn = if opts[:origin], do: put_req_header(conn, "origin", opts[:origin]), else: conn

    conn =
      Enum.reduce(opts[:headers] || [], conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    router.call(conn, router.init([]))
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> Enum.join(", ")

  defp json(conn), do: Jason.decode!(conn.resp_body)
end
