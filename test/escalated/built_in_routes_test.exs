defmodule Escalated.BuiltInRoutesTest do
  @moduledoc """
  The shared frontend calls Ziggy-style `route('escalated....', params)`.
  Escalated.Routes ships those names with this package's real paths, shared as
  the `ziggy` Inertia prop, so hosts no longer hand-map them in a
  `window.route` shim. An unmapped name leaves its button pointing at `#`.
  """
  use Escalated.PageCase

  alias Escalated.Routes
  alias Escalated.Test.{Router, SharedPropsRouter}

  # test/fixtures/frontend-route-names.txt (see its header to regenerate).
  @names_file Path.join(__DIR__, "../fixtures/frontend-route-names.txt")

  # Names the shared frontend calls that this backend does not serve. Each one
  # is a feature missing here, not a mapping left out; serving one means adding
  # it to Escalated.Routes and taking it off this list.
  @not_served [
    # The host's sign-in page: Escalated does not own sign-in, so the host maps
    # it (`config :escalated, route_overrides: %{"login" => "/users/log_in"}`).
    "login",
    # Automations are created and edited through the JSON endpoints only; there
    # are no create/edit pages (the routes exclude :new and :edit).
    "escalated.admin.automations.create",
    "escalated.admin.automations.edit",
    # Plugins are host-registered modules; there is no upload of plugin archives.
    "escalated.admin.plugins.upload"
  ]

  @prefix "/support"

  setup do
    on_exit(fn ->
      Enum.each([:route_prefix, :route_overrides], &Application.delete_env(:escalated, &1))
    end)

    :ok
  end

  defp frontend_names do
    @names_file
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  end

  describe "the built-in list" do
    test "covers every name the frontend calls, or lists it as not served" do
      routes = Routes.routes()
      missing = Enum.reject(frontend_names(), &(Map.has_key?(routes, &1) or &1 in @not_served))

      assert missing == [],
             "frontend route names with no mapping and no not-served entry: #{inspect(missing)}"
    end

    test "keeps the not-served list honest" do
      served = Enum.filter(@not_served, &Map.has_key?(Routes.routes(), &1))
      assert served == [], "listed as not served but mapped: #{inspect(served)}"

      unknown = @not_served -- frontend_names()
      assert unknown == [], "not-served names the frontend no longer calls: #{inspect(unknown)}"
    end

    test "uses the Ziggy shape: no leading slash, {param} placeholders, upper-case methods" do
      for {name, route} <- Routes.routes() do
        assert is_binary(route.uri) and not String.starts_with?(route.uri, "/"), name
        refute route.uri =~ ~r{/:\w}, "#{name} uses a :param segment: #{route.uri}"
        assert route.methods != [] and Enum.all?(route.methods, &(&1 == String.upcase(&1))), name
      end
    end

    # Each listed uri and method resolves, through the router a host mounts, to
    # the route with the same shape: a literal segment matched literally and a
    # {param} matched by a :param, so no name lands on a catch-all or on a
    # neighbouring route that happens to take the same path.
    test "every uri and method is a real mounted route" do
      problems =
        for {name, route} <- Routes.routes(),
            method <- route.methods,
            method != "HEAD",
            problem = mismatch(route.uri, method),
            do: "#{name} #{method} /#{route.uri}: #{problem}"

      assert problems == [], Enum.join(problems, "\n")
    end
  end

  defp mismatch(uri, method) do
    path = "/" <> String.replace(uri, ~r/\{\w+\}/, "1")

    case Phoenix.Router.route_info(Router, method, path, "localhost") do
      :error ->
        "no route"

      %{route: pattern} ->
        expected = Regex.replace(~r/\{\w+\}/, "/" <> uri, ":")
        actual = Regex.replace(~r/:\w+/, pattern, ":")
        if expected == actual, do: nil, else: "matched #{pattern}"
    end
  end

  describe "the prefix" do
    test "follows route_prefix" do
      Application.put_env(:escalated, :route_prefix, "/helpdesk/")

      assert Routes.routes()["escalated.agent.tickets.show"].uri ==
               "helpdesk/agent/tickets/{ticket}"

      Application.put_env(:escalated, :route_prefix, "/")
      assert Routes.routes()["escalated.admin.tickets.index"].uri == "admin/tickets"
    end
  end

  describe "the ziggy prop" do
    test "is on an Escalated Inertia response, with the prefix the router is mounted at" do
      agent = host_user!(%{is_agent: true})

      props =
        visit(:get, "#{@prefix}/agent/tickets?status=open", agent)
        |> page!("Escalated/Agent/TicketIndex")

      ziggy = props["ziggy"]
      assert_keys(ziggy, ~w(url port defaults routes location), "ziggy")
      assert ziggy["url"] == "http://www.example.com"
      assert ziggy["port"] == nil
      assert ziggy["defaults"] == %{}
      assert ziggy["location"] == "http://www.example.com/support/agent/tickets?status=open"

      assert ziggy["routes"]["escalated.agent.tickets.show"] == %{
               "uri" => "support/agent/tickets/{ticket}",
               "methods" => ["GET", "HEAD"]
             }
    end

    test "is shared by ShareInertiaData too, with the configured prefix" do
      Application.put_env(:escalated, :route_prefix, "/helpdesk")
      agent = host_user!(%{is_agent: true})

      conn =
        conn(:get, "#{@prefix}/agent/tickets")
        |> init_test_session(%{})
        |> assign(:current_user, agent)
        |> put_req_header("x-inertia", "true")
        |> put_req_header("x-inertia-version", inertia_version())
        |> SharedPropsRouter.call(SharedPropsRouter.init([]))

      props = page!(conn, "Escalated/Agent/TicketIndex")

      assert props["ziggy"]["routes"]["escalated.admin.tickets.show"]["uri"] ==
               "helpdesk/admin/tickets/{ticket}"
    end
  end

  describe "the host's mapping wins" do
    test "route_overrides replace, add and remove names" do
      Application.put_env(:escalated, :route_overrides, %{
        "login" => "/users/log_in",
        "escalated.customer.kb.index" => %{uri: "/help", methods: ["get"]},
        "escalated.admin.reports" => nil
      })

      routes = Routes.routes()
      assert routes["login"] == %{uri: "users/log_in", methods: ["GET", "HEAD"]}
      assert routes["escalated.customer.kb.index"] == %{uri: "help", methods: ["GET"]}
      refute Map.has_key?(routes, "escalated.admin.reports")
      assert routes["escalated.admin.tickets.index"].uri == "support/admin/tickets"
    end

    test "a ziggy prop the host shares is left as it is" do
      agent = host_user!(%{is_agent: true})
      host_table = %{routes: %{"login" => %{uri: "users/log_in", methods: ["GET"]}}}

      conn =
        conn(:get, "#{@prefix}/agent/tickets")
        |> init_test_session(%{})
        |> assign(:current_user, agent)
        |> put_req_header("x-inertia", "true")
        |> put_req_header("x-inertia-version", inertia_version())
        |> Inertia.Controller.assign_prop(:ziggy, host_table)
        |> Router.call(Router.init([]))

      props = page!(conn, "Escalated/Agent/TicketIndex")

      assert props["ziggy"] == %{
               "routes" => %{"login" => %{"uri" => "users/log_in", "methods" => ["GET"]}}
             }
    end
  end

  describe "the route() helper" do
    test "installs only when the page has no window.route and honours window.Ziggy" do
      js = Routes.helper_script()
      assert js =~ "if (typeof window.route === 'function') return;"
      assert js =~ "(window.Ziggy && window.Ziggy.routes) ||"
      assert js =~ "console.warn('[escalated] no route named ' + name);"
      assert js =~ "return '#';"
      assert js =~ "page.props && page.props.ziggy"
    end

    test "renders as a script tag with an escaped nonce" do
      {:safe, iodata} = Routes.helper_tag(nonce: ~s(abc"x))
      html = IO.iodata_to_binary(iodata)
      assert html =~ ~r{^<script nonce="abc&quot;x">}
      assert html =~ "window.route = function (name, params)"
      assert String.ends_with?(html, "</script>")

      {:safe, plain} = Routes.helper_tag()
      assert IO.iodata_to_binary(plain) =~ ~r{^<script>}
    end
  end
end
