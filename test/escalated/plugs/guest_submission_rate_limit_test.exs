defmodule Escalated.Plugs.GuestSubmissionRateLimitTest do
  # The guest ticket and reply endpoints are unauthenticated and every accepted
  # request writes rows and sends mail, so on top of the shared widget and guest
  # budgets each has its own per-IP limit: 5 tickets and 10 replies a minute by
  # default. Mirrors escalated-dev/escalated-nestjs#130.
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.RateLimiter
  alias Escalated.Schemas.Ticket
  alias Escalated.Test.{GuestAccessHelpers, Router}
  alias Escalated.TestRepo

  defmodule TestBackend do
    @moduledoc false
    def check(bucket, key, max_requests, window_ms) do
      server = Application.fetch_env!(:escalated, :test_rate_limit_server)
      RateLimiter.check(bucket, key, max_requests, window_ms, server)
    end
  end

  setup do
    GuestAccessHelpers.configure()
    server = start_supervised!({RateLimiter, name: nil, clock: fn -> 0 end})

    # The shared budgets are raised out of the way so only the per-endpoint
    # limits under test can be what trips.
    put_envs(
      rate_limit_backend: TestBackend,
      test_rate_limit_server: server,
      widget_rate_limit: %{max_requests: 1_000, window_ms: 60_000},
      guest_rate_limit: %{max_requests: 1_000, window_ms: 60_000},
      widget_settings: %{enabled: true},
      guest_submission_rate_limit: %{}
    )

    :ok
  end

  test "the 6th widget ticket from one IP within a minute is answered 429" do
    assert statuses(6, &widget_ticket/1) == [201, 201, 201, 201, 201, 429]
    assert TestRepo.aggregate(Ticket, :count) == 5
  end

  test "the 6th API guest ticket from one IP within a minute is answered 429" do
    assert statuses(6, &api_ticket/1) == [201, 201, 201, 201, 201, 429]
  end

  test "a refused request carries Retry-After" do
    limit(tickets_per_minute: 1)
    widget_ticket(0)

    conn = widget_ticket(1)

    assert conn.status == 429
    assert conn.halted
    [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) in 1..60
  end

  test "the 11th guest reply from one IP within a minute is answered 429" do
    %{"reference" => reference, "guest_access_token" => token} = created(widget_ticket(0))

    out = statuses(11, fn _ -> widget_reply(reference, token) end)

    assert Enum.take(out, 10) == List.duplicate(201, 10)
    assert List.last(out) == 429
  end

  test "replies carrying a wrong guest token are counted" do
    limit(replies_per_minute: 2)

    assert statuses(3, fn _ -> widget_reply("ESC-1", "wrong") end) == [404, 404, 429]
  end

  test "API guest replies share the reply limit" do
    limit(replies_per_minute: 2)
    widget_reply("ESC-1", "wrong")

    assert statuses(2, fn _ -> api_reply("wrong") end) == [404, 429]
  end

  test "tickets and replies are counted separately" do
    statuses(5, &widget_ticket/1)

    assert statuses(1, fn _ -> widget_reply("ESC-1", "wrong") end) == [404]
  end

  test "each client IP is counted separately" do
    limit(tickets_per_minute: 1)
    widget_ticket(0)

    assert widget_ticket(1, {198, 51, 100, 7}).status == 201
  end

  test "the configured limit is honoured" do
    limit(tickets_per_minute: 2)

    assert statuses(3, &widget_ticket/1) == [201, 201, 429]
  end

  test "a host that throttles upstream can switch it off" do
    limit(enabled: false)

    assert Enum.all?(statuses(8, &widget_ticket/1), &(&1 == 201))
  end

  test "defaults match the reference" do
    defaults = Escalated.Plugs.GuestSubmissionRateLimit.defaults()

    assert defaults == %{enabled: true, tickets_per_minute: 5, replies_per_minute: 10}
  end

  defp limit(overrides),
    do: Application.put_env(:escalated, :guest_submission_rate_limit, Map.new(overrides))

  defp statuses(times, send), do: Enum.map(0..(times - 1), &send.(&1).status)

  # A distinct mailbox per call, so only the per-IP limit can be what trips.
  defp widget_ticket(n, ip \\ {203, 0, 113, 1}) do
    body =
      GuestAccessHelpers.proof("guest#{n}@example.test")
      |> Map.merge(%{"name" => "Guest", "subject" => "Help", "description" => "Details"})

    request(:post, "/support/widget/tickets", body, ip)
  end

  defp api_ticket(n) do
    body =
      GuestAccessHelpers.proof("api#{n}@example.test")
      |> Map.merge(%{"name" => "Guest", "subject" => "Help", "body" => "Details"})

    request(:post, "/support/api/v1/guest/tickets", body)
  end

  defp widget_reply(reference, token) do
    request(
      :post,
      "/support/widget/tickets/#{reference}/reply",
      %{"body" => "hi"},
      {203, 0, 113, 1},
      token: token
    )
  end

  defp api_reply(token),
    do: request(:post, "/support/api/v1/guest/tickets/#{token}/replies", %{"body" => "hi"})

  defp created(conn) do
    assert conn.status == 201
    Jason.decode!(conn.resp_body)
  end

  defp request(method, path, body, ip \\ {203, 0, 113, 1}, opts \\ []) do
    conn =
      conn(method, path, Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> init_test_session(%{})
      |> Map.put(:remote_ip, ip)

    conn = if opts[:token], do: put_req_header(conn, "x-guest-token", opts[:token]), else: conn

    Router.call(conn, Router.init([]))
  end

  defp put_envs(settings) do
    previous =
      Enum.map(settings, fn {key, _} -> {key, Application.fetch_env(:escalated, key)} end)

    Enum.each(settings, fn {key, value} -> Application.put_env(:escalated, key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)
  end
end
