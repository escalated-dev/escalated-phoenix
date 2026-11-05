defmodule Escalated.Embed do
  @moduledoc """
  Embedding the admin in the host's own admin panel (optional; ADR
  2026-11-05-embeddable-admin).

  Off by default. While `config :escalated, :ui, embed: [enabled: true]` is not
  set, every function here returns what the package did before the feature
  existed: the admin lives at `{route_prefix}/admin`, no prop or header
  changes.

      # config/config.exs (compile time: it decides which routes the router has)
      config :escalated, :ui,
        embed: [
          enabled: true,
          prefix: "/admin/support",
          middleware: [:require_admin],
          replace_admin_gate: false,
          layout: "Layouts/AdminLayout",
          root_view: {MyAppWeb.Layouts, :escalated_admin},
          mode: :layout,
          frame_ancestors: []
        ]

  `enabled`, `prefix`, `middleware` and `replace_admin_gate` shape the routes
  `escalated_routes/2` mounts, so they are read when the router compiles (set
  them in `config/config.exs`; Elixir refuses to boot if `config/runtime.exs`
  changes them later). `mode`, `layout`, `root_view` and `frame_ancestors` are
  read per request and may come from `config/runtime.exs`. See
  `docs/embedding-admin.md`.
  """

  @modes [:layout, :iframe]
  @private_key :escalated_embedded

  @defaults [
    enabled: false,
    mode: :layout,
    prefix: "admin/support",
    middleware: nil,
    replace_admin_gate: false,
    layout: nil,
    root_view: nil,
    frame_ancestors: []
  ]

  @doc "The defaults of every `:embed` key."
  def defaults, do: @defaults

  @doc "The embed settings: the defaults overlaid with `config :escalated, :ui, embed: [...]`."
  @spec config() :: keyword()
  def config do
    configured =
      case Application.get_env(:escalated, :ui) do
        ui when is_list(ui) -> Keyword.get(ui, :embed)
        %{} = ui -> Map.get(ui, :embed)
        _ -> nil
      end

    Keyword.merge(@defaults, normalize(configured))
  end

  defp normalize(nil), do: []
  defp normalize(%{} = map), do: Enum.map(map, fn {key, value} -> {to_atom(key), value} end)
  defp normalize(list) when is_list(list), do: list
  defp normalize(_), do: []

  defp to_atom(key) when is_atom(key), do: key
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp to_atom(key), do: String.to_existing_atom(to_string(key))

  @doc "Whether the admin is embedded (`ESCALATED_EMBED`)."
  @spec enabled?() :: boolean()
  def enabled?, do: truthy?(config()[:enabled])

  @doc "`:layout` (host layout or root view wraps the pages) or `:iframe`."
  @spec mode() :: :layout | :iframe
  def mode, do: parse_mode(config()[:mode])

  @doc false
  def parse_mode(value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      "iframe" -> :iframe
      _ -> :layout
    end
  end

  @doc "The modes `mode` accepts."
  def modes, do: @modes

  @doc "The host prefix the admin is mounted under while embedded, without slashes."
  @spec prefix() :: String.t()
  def prefix, do: trim_prefix(config()[:prefix])

  @doc false
  def trim_prefix(value) do
    case value |> to_string() |> String.trim() |> String.trim("/") do
      "" -> "admin/support"
      prefix -> prefix
    end
  end

  @doc "The absolute path the embedded admin lives at (`escalated.embed.base_url`)."
  @spec base_url() :: String.t()
  def base_url, do: "/" <> prefix()

  @doc "Whether the host's middleware replaces Escalated's admin gate on the embedded routes."
  @spec replaces_admin_gate?() :: boolean()
  def replaces_admin_gate?, do: truthy?(config()[:replace_admin_gate])

  @doc "The host layout name the frontend's `layouts` option should wrap embedded pages in."
  @spec layout() :: String.t() | nil
  def layout, do: blank_to_nil(config()[:layout])

  @doc "The root layout (`{module, template}`) for embedded responses, or nil."
  def root_view do
    case config()[:root_view] do
      {module, template} when is_atom(module) and (is_atom(template) or is_binary(template)) ->
        {module, template}

      _ ->
        nil
    end
  end

  @doc """
  The origins allowed to frame the admin in iframe mode: exact
  `scheme://host[:port]` http(s) origins. `*`, wildcards, paths, queries and
  credentials are dropped. A comma-separated string is accepted
  (`ESCALATED_EMBED_FRAME_ANCESTORS`).
  """
  @spec frame_ancestors() :: [String.t()]
  def frame_ancestors do
    config()[:frame_ancestors]
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_binary(value) -> String.split(value, ",")
      value -> [to_string(value)]
    end)
    |> Enum.map(&origin/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc "The `frame-ancestors` CSP directive for an embedded iframe response."
  @spec frame_ancestors_directive() :: String.t()
  def frame_ancestors_directive do
    String.trim("frame-ancestors 'self' " <> Enum.join(frame_ancestors(), " "))
  end

  @doc """
  Where the admin routes live: `{route_prefix}/admin`, or the host's prefix
  while embedded. Admin redirects and links are built from it.
  """
  @spec admin_base() :: String.t()
  def admin_base do
    if enabled?(),
      do: base_url(),
      else: Escalated.config(:route_prefix, "/support") <> "/admin"
  end

  @doc "`admin_base/0` followed by `path` (which starts with `/`)."
  @spec admin_path(String.t()) :: String.t()
  def admin_path(path), do: admin_base() <> path

  @doc "Marks `conn` as an embedded admin request (`Escalated.Plugs.ApplyEmbedContext`)."
  def mark(conn), do: Plug.Conn.put_private(conn, @private_key, true)

  @doc "Whether `conn` is served by an embedded admin route."
  @spec embedded?(Plug.Conn.t() | nil) :: boolean()
  def embedded?(%Plug.Conn{private: private}), do: Map.get(private, @private_key) == true
  def embedded?(_), do: false

  @doc """
  The `escalated.embed` shared prop. Shared only while embedding is on;
  `enabled` is true only on embedded admin responses.
  """
  @spec shared(Plug.Conn.t()) :: map()
  def shared(conn) do
    embedded = embedded?(conn)
    mode = mode()

    %{
      enabled: embedded,
      mode: Atom.to_string(mode),
      layout: layout(),
      route: if(embedded, do: route_name(conn), else: nil),
      base_url: base_url(),
      allowed_origins: if(mode == :iframe, do: frame_ancestors(), else: [])
    }
  end

  @doc """
  `escalated` props with `embed` and `navigation` added while embedding is on
  (Escalated.Plugs.ShareInertiaData); unchanged while it is off.
  """
  @spec put_props(map(), term(), Plug.Conn.t()) :: map()
  def put_props(props, user, conn) do
    if enabled?() do
      props
      |> Map.put(:embed, shared(conn))
      |> Map.put(:navigation, Escalated.AdminNavigation.for(user, conn))
    else
      props
    end
  end

  @doc """
  Updates the `escalated.embed` prop the host's pipeline already shared,
  once `conn` is known to be embedded (Escalated.Plugs.ApplyEmbedContext).
  """
  @spec reshare(Plug.Conn.t()) :: Plug.Conn.t()
  def reshare(conn) do
    shared = conn.private[:inertia_shared] || %{}

    case Map.get(shared, :escalated) do
      %{embed: _} = props ->
        Plug.Conn.put_private(
          conn,
          :inertia_shared,
          Map.put(shared, :escalated, Map.put(props, :embed, shared(conn)))
        )

      _ ->
        conn
    end
  end

  @doc """
  The frontend's name for the route `conn` is on (`Escalated.Routes`), the
  stand-in for a route name Phoenix routes do not have. nil when none matches.
  """
  @spec route_name(Plug.Conn.t()) :: String.t() | nil
  def route_name(%Plug.Conn{} = conn) do
    with router when not is_nil(router) <- conn.private[:phoenix_router],
         %{route: pattern} <-
           Phoenix.Router.route_info(router, conn.method, conn.path_info, conn.host) do
      shape = shape(pattern)

      Escalated.Routes.routes()
      |> Enum.filter(fn {_name, route} ->
        conn.method in route.methods and shape("/" <> route.uri) == shape
      end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()
      |> List.first()
    else
      _ -> nil
    end
  end

  defp shape(path) do
    path
    |> String.replace(~r/\{\w+\??\}/, ":")
    |> String.replace(~r/:\w+/, ":")
    |> String.replace(~r/\*\w+/, "*")
    |> String.trim_trailing("/")
  end

  @doc """
  Iframe mode, on an embedded response, at send time (after every plug and
  any host `register_before_send/2` callback registered later): drops
  `X-Frame-Options` and adds `Content-Security-Policy: frame-ancestors 'self'
  <origins>`. A host CSP already on the response is kept and this one is sent
  as a second policy. Nothing else is touched.
  """
  @spec decorate_response(Plug.Conn.t()) :: Plug.Conn.t()
  def decorate_response(conn) do
    if enabled?() and mode() == :iframe and embedded?(conn) do
      headers =
        Enum.reject(conn.resp_headers, fn {name, _} ->
          String.downcase(name) == "x-frame-options"
        end)

      %{
        conn
        | resp_headers: headers ++ [{"content-security-policy", frame_ancestors_directive()}]
      }
    else
      conn
    end
  end

  @doc false
  def truthy?(value), do: value in [true, "true", "TRUE", "True", "1", 1, "yes", "on"]

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case value |> to_string() |> String.trim() do
      "" -> nil
      text -> text
    end
  end

  defp origin(value) do
    value = String.trim(value)

    with false <- value == "" or String.contains?(value, "*"),
         %URI{scheme: scheme, host: host, port: port, userinfo: nil, query: nil, fragment: nil} =
           uri
         when scheme in ["http", "https"] and is_binary(host) and host != "" <-
           URI.parse(value),
         true <- uri.path in [nil, "", "/"] do
      host = String.downcase(host)
      default_port = if scheme == "https", do: 443, else: 80

      if port == default_port or is_nil(port),
        do: "#{scheme}://#{host}#{explicit_port(value, port)}",
        else: "#{scheme}://#{host}:#{port}"
    else
      _ -> nil
    end
  end

  # Keeps an explicitly written default port (https://a.example:443), as the
  # browser compares origins by what the page serves; drops the implied one.
  defp explicit_port(value, port) do
    if port && Regex.match?(~r{://[^/]+:#{port}(/|$)}, value), do: ":#{port}", else: ""
  end
end
