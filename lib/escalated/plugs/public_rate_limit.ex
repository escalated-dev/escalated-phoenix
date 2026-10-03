defmodule Escalated.Plugs.PublicRateLimit do
  @moduledoc """
  Public-route throttling using the transport's remote IP, never a caller's
  forwarding header. Hosts behind a proxy must configure trusted proxies first.
  IPv6 clients are charged per /64 (see `Escalated.RateLimiter.client_key/1`).
  Backend errors and invalid configuration fail closed with HTTP 503.
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    config = config(Keyword.fetch!(opts, :config), %{max_requests: 20, window_ms: 60_000})

    if valid_config?(config) do
      key = Escalated.RateLimiter.client_key(conn.remote_ip)
      enforce(conn, [{bucket, key, config.max_requests, config.window_ms}])
    else
      unavailable(conn)
    end
  rescue
    _ -> unavailable(conn)
  end

  @doc false
  # Merges a configured limit over its defaults.
  def config(name, defaults), do: Map.merge(defaults, Escalated.config(name, %{}))

  @doc false
  # Charges each `{bucket, key, max_requests, window_ms}` in order and responds
  # to the first refusal. Backend errors fail closed with HTTP 503.
  def enforce(conn, checks) do
    backend = Escalated.config(:rate_limit_backend, Escalated.RateLimiter)

    Enum.reduce_while(checks, conn, fn {bucket, key, max_requests, window_ms}, conn ->
      case respond(backend.check(bucket, key, max_requests, window_ms), conn) do
        %Plug.Conn{halted: true} = halted -> {:halt, halted}
        allowed -> {:cont, allowed}
      end
    end)
  rescue
    _ -> unavailable(conn)
  catch
    :exit, _ -> unavailable(conn)
  end

  @doc false
  def unavailable(conn) do
    conn
    |> put_resp_header("retry-after", "1")
    |> put_resp_header("cache-control", "no-store")
    |> put_status(503)
    |> Phoenix.Controller.json(%{error: "Service temporarily unavailable."})
    |> halt()
  end

  @doc false
  def valid_config?(config) do
    is_integer(config.max_requests) and config.max_requests > 0 and
      is_integer(config.window_ms) and config.window_ms > 0
  end

  defp respond(:allow, conn), do: conn

  defp respond({:deny, retry_ms}, conn) when is_integer(retry_ms) and retry_ms > 0 do
    conn
    |> put_resp_header("retry-after", to_string(max(div(retry_ms + 999, 1000), 1)))
    |> put_resp_header("cache-control", "no-store")
    |> put_status(429)
    |> Phoenix.Controller.json(%{error: "Too many requests. Please try again later."})
    |> halt()
  end

  defp respond(_, conn), do: unavailable(conn)
end
