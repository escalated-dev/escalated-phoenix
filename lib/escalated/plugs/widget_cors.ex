defmodule Escalated.Plugs.WidgetCors do
  @moduledoc """
  CORS for the widget routes, so other sites can embed the widget.

  Only origins allowed by `Escalated.WidgetOrigins` (the
  `:widget_allowed_origins` config plus the `widget_allowed_origins` admin
  setting) get CORS headers. A request from such a site:

    * gets `Access-Control-Allow-Origin` on every response, errors and rate
      limit answers included, and preflights are answered here;
    * is marked so `Plug.CSRFProtection` skips it, since it carries no session
      cookie and so no CSRF token, and has nothing a token would protect;
    * always runs as a guest: `:current_user` is cleared and the session is
      neither read for a user nor written back.

  Everything else passes through untouched, so nothing changes until an origin
  is listed. `Escalated.Router.escalated_routes/2` and
  `escalated_widget_routes/1` run this plug first in the widget scope. To skip
  CSRF for embedding sites, the host also runs it in the widget pipeline before
  `:protect_from_forgery` (see the README); running it twice is harmless.
  """
  @behaviour Plug
  import Plug.Conn

  alias Escalated.{Tenancy, WidgetOrigins}

  @seen :escalated_widget_cors
  @origin :escalated_widget_origin

  @methods "GET, POST, OPTIONS"
  @headers "Accept, Authorization, Content-Type, X-Requested-With"

  def init(opts), do: opts

  # A second run (the package's own scope after the host's pipeline) only has
  # to undo whatever user the host's later plugs assigned.
  def call(%Plug.Conn{private: %{@seen => true}} = conn, _opts) do
    if conn.private[@origin], do: as_guest(conn), else: conn
  end

  def call(conn, _opts) do
    conn = put_private(conn, @seen, true)
    origin = WidgetOrigins.cross_origin(conn)
    allowed = is_binary(origin) and allowed?(conn, origin)

    cond do
      preflight?(conn) -> preflight(conn, allowed && origin)
      allowed -> embedded(conn, origin)
      true -> conn
    end
  end

  @doc "The allowed embedding origin of this request, or nil."
  def origin(%Plug.Conn{private: private}), do: Map.get(private, @origin)

  defp embedded(conn, origin) do
    conn
    |> put_private(@origin, origin)
    |> put_private(:plug_skip_csrf_protection, true)
    |> as_guest()
    |> register_before_send(&cors_headers(&1, origin))
  end

  defp preflight?(conn) do
    conn.method == "OPTIONS" and get_req_header(conn, "access-control-request-method") != []
  end

  defp preflight(conn, origin) do
    conn =
      if is_binary(origin) do
        conn
        |> put_resp_header("access-control-allow-methods", @methods)
        |> put_resp_header("access-control-allow-headers", @headers)
        |> put_resp_header("access-control-max-age", to_string(max_age()))
        |> cors_headers(origin)
      else
        vary_origin(conn)
      end

    conn |> send_resp(204, "") |> halt()
  end

  defp as_guest(conn) do
    conn = assign(conn, :current_user, nil)

    # Never read a user from, or write anything back to, the browser session
    # of whoever is signed in on this site.
    if Map.get(conn.private, :plug_session_fetch) == :done,
      do: configure_session(conn, ignore: true),
      else: conn
  end

  defp cors_headers(conn, origin) do
    conn =
      if get_resp_header(conn, "access-control-allow-origin") == ["*"],
        do: conn,
        else: put_resp_header(conn, "access-control-allow-origin", origin)

    conn
    |> put_resp_header("access-control-expose-headers", "Retry-After")
    |> vary_origin()
  end

  defp vary_origin(conn) do
    vary =
      conn
      |> get_resp_header("vary")
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    vary = if "Origin" in vary, do: vary, else: vary ++ ["Origin"]
    put_resp_header(conn, "vary", Enum.join(vary, ", "))
  end

  defp max_age do
    case Escalated.config(:widget_preflight_max_age, 600) do
      age when is_integer(age) and age >= 0 -> age
      _ -> 600
    end
  end

  # Before Escalated.Plugs.ResolveTenant has run there is no tenant to read the
  # admin setting for. Resolve it the same trusted way; when that is not
  # possible yet, only the config list is consulted.
  defp allowed?(conn, origin) do
    if Tenancy.enabled?() and not tenant_set?() do
      case resolve_tenant(conn) do
        nil -> WidgetOrigins.allows_configured?(origin)
        id -> Tenancy.run(id, fn -> WidgetOrigins.allows?(origin) end)
      end
    else
      WidgetOrigins.allows?(origin)
    end
  end

  defp tenant_set? do
    is_binary(Tenancy.current_id!())
  rescue
    _ -> false
  end

  defp resolve_tenant(conn) do
    id =
      case Tenancy.resolve(conn) do
        {:ok, value} -> value
        value -> value
      end

    Tenancy.validate_id!(id)
  rescue
    _ -> nil
  end
end
