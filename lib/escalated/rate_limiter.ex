defmodule Escalated.RateLimiter do
  @moduledoc """
  Bounded, node-local fixed-window limits for public requests.

  The supervised process owns the ETS table and serializes admission. Request
  process exits cannot reset the counters, and concurrent requests cannot spend
  the same remaining slot. Hosts may configure `:rate_limit_backend` with a
  module implementing `check/4` for a shared cluster-wide store.
  """
  use GenServer

  def start_link(opts \\ []) do
    server_opts =
      case Keyword.get(opts, :name, __MODULE__) do
        nil -> []
        name -> [name: name]
      end

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc """
  Normalizes a client address into the identity a limit is charged to.

  An IPv6 client usually controls a whole /64, so every address in it shares one
  key; IPv4-mapped IPv6 addresses are keyed as the IPv4 address they carry.
  """
  def client_key({_, _, _, _} = ipv4), do: ipv4

  def client_key({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)}

  def client_key({a, b, c, d, _, _, _, _}), do: {a, b, c, d, 0, 0, 0, 0}
  def client_key(other), do: other

  @doc "Returns `:allow`, `{:deny, retry_after_ms}`, or `{:error, reason}`."
  def check(bucket, key, max_requests, window_ms, server \\ __MODULE__)
      when is_integer(max_requests) and max_requests > 0 and is_integer(window_ms) and
             window_ms > 0 do
    GenServer.call(server, {:check, {bucket, key}, max_requests, window_ms})
  end

  @impl true
  def init(opts) do
    state = %{
      table: :ets.new(__MODULE__, [:set, :private]),
      max_entries: Keyword.get(opts, :max_entries, 50_000),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    }

    schedule_sweep()
    {:ok, state}
  end

  @impl true
  def handle_call({:check, key, limit, window}, _from, state) do
    now = state.clock.()

    result =
      case :ets.lookup(state.table, key) do
        [{^key, count, expires_at}] when expires_at > now ->
          admit_existing(state.table, key, count, expires_at, limit, now)

        _ ->
          admit_new(state, key, now, window)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep(state.table, state.clock.())
    schedule_sweep()
    {:noreply, state}
  end

  defp admit_existing(_table, _key, count, expires_at, limit, now) when count >= limit,
    do: {:deny, expires_at - now}

  defp admit_existing(table, key, count, expires_at, _limit, _now) do
    :ets.insert(table, {key, count + 1, expires_at})
    :allow
  end

  defp admit_new(state, key, now, window) do
    if :ets.info(state.table, :size) >= state.max_entries, do: sweep(state.table, now)

    if :ets.member(state.table, key) or :ets.info(state.table, :size) < state.max_entries do
      :ets.insert(state.table, {key, 1, now + window})
      :allow
    else
      {:error, :capacity}
    end
  end

  defp sweep(table, now) do
    :ets.select_delete(table, [{{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", now}], [true]}])
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end
