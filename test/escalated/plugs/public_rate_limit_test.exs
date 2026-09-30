defmodule Escalated.Plugs.PublicRateLimitTest do
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Plugs.GuestRateLimit
  alias Escalated.RateLimiter
  alias Escalated.Test.Router

  defmodule TestBackend do
    @moduledoc false
    def check(bucket, key, max_requests, window_ms) do
      server = Application.fetch_env!(:escalated, :test_rate_limit_server)
      RateLimiter.check(bucket, key, max_requests, window_ms, server)
    end
  end

  defmodule UnavailableBackend do
    @moduledoc false
    def check(_, _, _, _), do: exit(:unavailable)
  end

  setup do
    server = start_supervised!({RateLimiter, name: nil, clock: fn -> 0 end})

    settings = [
      rate_limit_backend: TestBackend,
      test_rate_limit_server: server,
      guest_rate_limit: %{max_requests: 2, window_ms: 1501},
      widget_rate_limit: %{max_requests: 2, window_ms: 1501}
    ]

    previous =
      Enum.map(settings, fn {key, _} -> {key, Application.fetch_env(:escalated, key)} end)

    Enum.each(settings, fn {key, value} -> Application.put_env(:escalated, key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "guest creation is throttled through the mounted API" do
    Escalated.Test.GuestAccessHelpers.configure()

    body =
      Escalated.Test.GuestAccessHelpers.proof("pat@example.com")
      |> Map.merge(%{"name" => "Pat", "subject" => "Help", "body" => "Details"})

    assert request(:post, "/support/api/v1/guest/tickets", body).status == 201
    assert request(:post, "/support/api/v1/guest/tickets", body).status == 201
    assert_throttled(request(:post, "/support/api/v1/guest/tickets", body))
  end

  test "changing guessed tokens cannot reset the guest lookup budget" do
    assert request(:get, "/support/api/v1/guest/tickets/missing-a").status == 404
    assert request(:get, "/support/api/v1/guest/tickets/missing-b").status == 404
    assert_throttled(request(:get, "/support/api/v1/guest/tickets/missing-c"))
  end

  test "guest ratings share the guest budget" do
    assert request(:post, "/support/guest/tickets/missing-a/rate", %{rating: 5}).status == 404
    assert request(:get, "/support/api/v1/guest/tickets/missing-b").status == 404
    assert_throttled(request(:post, "/support/guest/tickets/missing-c/rate", %{rating: 5}))
  end

  test "widget and chat share their own budget" do
    assert request(:get, "/support/widget/config").status == 200
    assert request(:get, "/support/widget/chat/availability").status == 200
    assert_throttled(request(:get, "/support/widget/config"))
    assert request(:get, "/support/api/v1/guest/tickets/missing").status == 404
  end

  test "forwarded headers do not let a caller choose a fresh identity" do
    for ip <- ["1.1.1.1", "2.2.2.2"] do
      refute conn(:get, "/")
             |> put_req_header("x-forwarded-for", ip)
             |> GuestRateLimit.call([])
             |> Map.get(:halted)
    end

    conn(:get, "/")
    |> put_req_header("x-forwarded-for", "3.3.3.3")
    |> GuestRateLimit.call([])
    |> assert_throttled()

    refute %{conn(:get, "/") | remote_ip: {203, 0, 113, 1}}
           |> GuestRateLimit.call([])
           |> Map.get(:halted)
  end

  test "backend outages and invalid limits fail closed" do
    Application.put_env(:escalated, :rate_limit_backend, UnavailableBackend)
    unavailable = request(:post, "/support/api/v1/guest/tickets", %{})
    assert unavailable.status == 503
    assert unavailable.halted

    Application.put_env(:escalated, :rate_limit_backend, TestBackend)
    Application.put_env(:escalated, :guest_rate_limit, %{max_requests: 0})
    assert request(:post, "/support/api/v1/guest/tickets", %{}).status == 503
  end

  defp assert_throttled(conn) do
    assert conn.status == 429
    assert conn.halted
    assert get_resp_header(conn, "retry-after") == ["2"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  defp request(method, path, body \\ nil) do
    conn =
      if body do
        conn(method, path, Jason.encode!(body))
        |> put_req_header("content-type", "application/json")
      else
        conn(method, path)
      end

    conn
    |> init_test_session(%{})
    |> put_req_header("accept", "application/json")
    |> Router.call(Router.init([]))
  end
end
