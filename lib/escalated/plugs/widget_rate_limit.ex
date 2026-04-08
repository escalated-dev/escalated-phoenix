defmodule Escalated.Plugs.WidgetRateLimit do
  @moduledoc """
  Simple rate-limiting plug for widget endpoints.

  Uses an ETS table to track request counts per IP address. Requests
  exceeding the configured limit within the window are rejected with
  HTTP 429.

  ## Configuration

      config :escalated,
        widget_rate_limit: %{
          max_requests: 20,
          window_ms: 60_000
        }
  """
  import Plug.Conn
  @behaviour Plug

  @table :escalated_widget_rate_limit

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ensure_table()

    ip = client_ip(conn)
    config = rate_limit_config()
    now = System.monotonic_time(:millisecond)
    window = config.window_ms

    # Clean old entries and count recent requests
    key = {:widget_rate, ip}

    timestamps =
      case :ets.lookup(@table, key) do
        [{^key, ts_list}] -> ts_list
        [] -> []
      end

    recent = Enum.filter(timestamps, fn ts -> now - ts < window end)

    if length(recent) >= config.max_requests do
      conn
      |> put_resp_header("retry-after", to_string(div(window, 1000)))
      |> put_status(429)
      |> Phoenix.Controller.json(%{error: "Too many requests. Please try again later."})
      |> halt()
    else
      :ets.insert(@table, {key, [now | recent]})
      conn
    end
  end

  defp ensure_table do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table])
      _ -> @table
    end
  end

  defp client_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp rate_limit_config do
    defaults = %{max_requests: 20, window_ms: 60_000}
    configured = Escalated.config(:widget_rate_limit, %{})
    Map.merge(defaults, configured)
  end
end
