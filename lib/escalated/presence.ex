defmodule Escalated.Presence do
  @moduledoc """
  Who else has a ticket open, for the shared `PresenceIndicator`.

  The page posts to `escalated.{agent,admin}.tickets.presence` every few
  seconds and shows the other viewers it gets back. Laravel keeps the same
  heartbeat in its cache for 60 seconds; this keeps it node-local in ETS for
  the same time. A host running several nodes sees only the viewers on the
  node that answered, which is what a per-node cache gives Laravel too.
  """
  use GenServer

  @ttl_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Records `viewer` (`%{id, name}`) on `ticket_id` and returns the other
  viewers seen within the last minute.
  """
  def heartbeat(ticket_id, viewer, server \\ __MODULE__) do
    GenServer.call(server, {:heartbeat, to_string(ticket_id), viewer})
  end

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    {:ok, %{table: :ets.new(__MODULE__, [:set, :private]), clock: clock}}
  end

  @impl true
  def handle_call({:heartbeat, ticket, viewer}, _from, state) do
    now = state.clock.()
    viewer_key = to_string(viewer.id)

    :ets.insert(state.table, {{ticket, viewer_key}, viewer, now + @ttl_ms})
    :ets.select_delete(state.table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])

    others =
      state.table
      |> :ets.match_object({{ticket, :_}, :_, :_})
      |> Enum.reject(fn {{_t, key}, _v, _exp} -> key == viewer_key end)
      |> Enum.map(fn {_key, v, _exp} -> v end)
      |> Enum.sort_by(&to_string(&1.id))

    {:reply, others, state}
  end
end
