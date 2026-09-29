defmodule Escalated.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Escalated.RateLimiter

  setup do
    clock = start_supervised!({Agent, fn -> -10_000 end})

    server =
      start_supervised!(
        {RateLimiter, name: nil, max_entries: 2, clock: fn -> Agent.get(clock, & &1) end}
      )

    %{server: server, clock: clock}
  end

  test "concurrent callers cannot spend the same slot", %{server: server} do
    results =
      1..100
      |> Task.async_stream(fn _ -> RateLimiter.check(:guest, :same_ip, 10, 60_000, server) end,
        max_concurrency: 100
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :allow)) == 10
    assert Enum.count(results, &(&1 == {:deny, 60_000})) == 90
  end

  test "admission survives the request process exiting", %{server: server} do
    assert :allow =
             Task.async(fn -> RateLimiter.check(:guest, :same_ip, 1, 60_000, server) end)
             |> Task.await()

    assert {:deny, 60_000} = RateLimiter.check(:guest, :same_ip, 1, 60_000, server)
  end

  test "denied calls do not extend a window and expiry restores admission", context do
    assert :allow = RateLimiter.check(:guest, :same_ip, 1, 60_000, context.server)
    Agent.update(context.clock, fn _ -> 49_501 end)
    assert {:deny, 499} = RateLimiter.check(:guest, :same_ip, 1, 60_000, context.server)
    Agent.update(context.clock, fn _ -> 50_000 end)
    assert :allow = RateLimiter.check(:guest, :same_ip, 1, 60_000, context.server)
  end

  test "buckets are independent and memory saturation fails closed", context do
    assert :allow = RateLimiter.check(:guest, :same_ip, 1, 60_000, context.server)
    assert :allow = RateLimiter.check(:widget, :same_ip, 1, 60_000, context.server)
    assert {:error, :capacity} = RateLimiter.check(:guest, :new_ip, 1, 60_000, context.server)
    assert {:deny, 60_000} = RateLimiter.check(:guest, :same_ip, 1, 60_000, context.server)

    Agent.update(context.clock, fn _ -> 50_000 end)
    assert :allow = RateLimiter.check(:guest, :new_ip, 1, 60_000, context.server)
  end
end
