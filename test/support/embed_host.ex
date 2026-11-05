defmodule Escalated.Test.EmbedHost.Layouts do
  @moduledoc false
  use Phoenix.Component

  # The host's normal root layout.
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head><title>Host app</title></head>
      <body><main id="host-root">{@inner_content}</main></body>
    </html>
    """
  end

  # The host's admin root layout, set as `root_view` for embedded admin
  # responses: the host's chrome, the admin menu from
  # Escalated.admin_navigation/2 and the Inertia page. docs/embedding-admin.md
  # shows this template (section 2).
  def escalated_admin(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Host admin</title>
      </head>
      <body>
        <header id="host-admin-header">Host admin</header>
        <div class="flex">
          <aside id="host-admin-menu">
            <p class="menu-heading">Support</p>
            <ul>
              <li :for={item <- Escalated.admin_navigation(@conn.assigns[:current_user], @conn)}>
                <a
                  href={item.url}
                  class={if item.active, do: "active"}
                  aria-current={if item.active, do: "page"}
                >
                  {item.label}
                </a>
              </li>
            </ul>
          </aside>
          <main id="host-admin-main">{@inner_content}</main>
        </div>
      </body>
    </html>
    """
  end
end

defmodule Escalated.Test.EmbedHost.HostAdmin do
  @moduledoc false

  # Stands in for the host's own admin middleware (e.g. `:require_admin`): it
  # marks the response so a test can see it ran, and refuses a request that
  # carries `x-host-deny`.
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = put_resp_header(conn, "x-host-admin", "1")

    if get_req_header(conn, "x-host-deny") == [] do
      conn
    else
      conn |> send_resp(403, "refused by the host") |> halt()
    end
  end
end

defmodule Escalated.Test.EmbedHost.LateFrameOptions do
  @moduledoc false

  # Host middleware that sets X-Frame-Options when the response is sent, the
  # latest a plug can; the embed headers still win on embedded responses.
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    register_before_send(conn, &put_resp_header(&1, "x-frame-options", "DENY"))
  end
end

defmodule Escalated.Test.EmbedHost do
  @moduledoc false

  # Host routers with the admin embedded. `escalated_routes/2` reads the route
  # keys of `config :escalated, :ui, embed:` when the router compiles, so each
  # router is compiled here with that configuration in place. The runtime keys
  # (mode, layout, root_view, frame_ancestors) are read per request, so a test
  # changes them with `put_embed/1`.

  @base [
    enabled: true,
    prefix: "/admin/support",
    middleware: [:host_admin],
    layout: "Layouts/AdminLayout"
  ]

  def base, do: @base

  @doc "Sets the embed configuration (merged over the base) for this test."
  def put_embed(overrides \\ []) do
    Application.put_env(:escalated, :ui, embed: Keyword.merge(@base, overrides))
  end

  def clear_embed, do: Application.delete_env(:escalated, :ui)

  @doc """
  The host router compiled with `embed` in place: the host's browser pipeline
  (with `put_secure_browser_headers`, which sends X-Frame-Options, and
  ShareInertiaData), a `:host_admin` pipeline and Escalated mounted at
  /support.
  """
  def router!(name, embed) do
    unless Code.ensure_loaded?(name) do
      previous = Application.get_env(:escalated, :ui)
      Application.put_env(:escalated, :ui, embed: embed)

      try do
        Code.compile_quoted(router_ast(name))
      after
        if previous,
          do: Application.put_env(:escalated, :ui, previous),
          else: Application.delete_env(:escalated, :ui)
      end
    end

    name
  end

  @doc """
  A request through `router`. `inertia: true` (default) sends it as an Inertia
  visit; `headers` are extra request headers.
  """
  def visit(router, method, path, user, opts \\ []) do
    import Plug.Conn
    import Plug.Test

    conn =
      case Keyword.get(opts, :body) do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    conn =
      conn
      |> init_test_session(%{})
      |> then(fn conn -> if user, do: assign(conn, :current_user, user), else: conn end)

    conn =
      Enum.reduce(Keyword.get(opts, :headers, []), conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    conn =
      if Keyword.get(opts, :inertia, true) do
        conn
        |> put_req_header("x-inertia", "true")
        |> put_req_header("x-inertia-version", Escalated.PageCase.inertia_version())
      else
        conn
      end

    router.call(conn, router.init([]))
  end

  defp router_ast(name) do
    quote do
      defmodule unquote(name) do
        @moduledoc false
        use Phoenix.Router
        use Escalated.Router
        import Phoenix.Controller

        @before_compile Escalated.Test.RouteTable

        pipeline :browser do
          plug Plug.Parsers,
            parsers: [:urlencoded, :json],
            pass: ["*/*"],
            json_decoder: Jason

          plug :fetch_session
          plug :fetch_flash
          plug :accepts, ["html", "json"]
          plug :put_root_layout, html: {Escalated.Test.EmbedHost.Layouts, :root}
          # Phoenix 1.8 sends `frame-ancestors 'self'` in a CSP here; many
          # hosts also send X-Frame-Options.
          plug :put_secure_browser_headers, %{"x-frame-options" => "SAMEORIGIN"}
          plug Inertia.Plug
          plug Escalated.Plugs.ShareInertiaData
        end

        pipeline :host_admin do
          plug Escalated.Test.EmbedHost.HostAdmin
          plug Escalated.Test.EmbedHost.LateFrameOptions
        end

        scope "/" do
          pipe_through :browser
          escalated_routes("/support", api: true)
        end
      end
    end
  end
end
