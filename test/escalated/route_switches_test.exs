defmodule Escalated.RouteSwitchesTest do
  @moduledoc """
  `config :escalated, routes: [...]`: the public widget and guest routes are
  mounted only while their switch is on, and `customer_middleware` guards the
  customer ticket, CSAT and knowledge-base routes. Each switch is read when the
  host's router compiles, so each case compiles a router with it in place.
  """
  use Escalated.PageCase

  alias Escalated.Test.EmbedHost

  @widget "/support/widget"
  @guest ["/support/guest", "/support/api/v1/guest", "/support/api/v1/mobile/guest"]

  setup do
    on_exit(fn ->
      Application.delete_env(:escalated, :knowledge_base_enabled)
      System.delete_env("ESCALATED_WIDGET_ENABLED")
      System.delete_env("ESCALATED_GUEST_ROUTES")
    end)

    :ok
  end

  # A host router compiled with `config :escalated, routes: routes`.
  defp router!(name, routes, body \\ nil) do
    unless Code.ensure_loaded?(name) do
      previous = Application.fetch_env(:escalated, :routes)
      Application.put_env(:escalated, :routes, routes)

      body =
        body ||
          quote do
            scope "/" do
              pipe_through :browser
              escalated_routes("/support", api: true)
            end
          end

      try do
        Code.compile_quoted(
          quote do
            defmodule unquote(name) do
              @moduledoc false
              use Phoenix.Router
              use Escalated.Router

              pipeline :browser do
                plug Plug.Parsers,
                  parsers: [:urlencoded, :json],
                  pass: ["*/*"],
                  json_decoder: Jason

                plug :fetch_session
                plug :fetch_flash
                plug Inertia.Plug
              end

              unquote(body)
            end
          end
        )
      after
        case previous do
          {:ok, value} -> Application.put_env(:escalated, :routes, value)
          :error -> Application.delete_env(:escalated, :routes)
        end
      end
    end

    name
  end

  defp paths(router), do: Enum.map(router.__routes__(), & &1.path)

  defp under?(paths, prefix), do: Enum.any?(paths, &String.starts_with?(&1, prefix))

  describe "defaults" do
    test "the widget and guest routes are mounted" do
      paths = paths(Escalated.Test.Router)

      assert under?(paths, @widget)
      for prefix <- @guest, do: assert(under?(paths, prefix), prefix)
    end

    test "an empty routes config changes nothing" do
      router = router!(Escalated.RouteSwitchesTest.EmptyRouter, [])
      assert Enum.sort(paths(router)) == Enum.sort(paths(Escalated.Test.Router))
    end
  end

  describe "widget: false" do
    test "no widget route is mounted by escalated_routes/2" do
      paths = paths(router!(Escalated.RouteSwitchesTest.NoWidget, widget: false))

      refute under?(paths, @widget)
      for prefix <- @guest, do: assert(under?(paths, prefix), prefix)
    end

    test "escalated_widget_routes/1 mounts nothing either" do
      body =
        quote do
          scope "/" do
            escalated_widget_routes("/support")
          end
        end

      router = router!(Escalated.RouteSwitchesTest.NoWidgetOnly, [widget: false], body)
      assert router.__routes__() == []
    end

    test "ESCALATED_WIDGET_ENABLED=false turns it off when the config does not say" do
      System.put_env("ESCALATED_WIDGET_ENABLED", "false")
      refute Escalated.Router.__route_switches__([]).widget
      assert Escalated.Router.__route_switches__(widget: true).widget
    end
  end

  describe "guest: false" do
    test "no guest portal, guest API or mobile guest route is mounted" do
      paths = paths(router!(Escalated.RouteSwitchesTest.NoGuest, guest: false))

      for prefix <- @guest, do: refute(under?(paths, prefix), prefix)
      assert under?(paths, @widget)
      assert "/support/tickets" in paths
    end

    test "ESCALATED_GUEST_ROUTES=false turns it off when the config does not say" do
      System.put_env("ESCALATED_GUEST_ROUTES", "false")
      refute Escalated.Router.__route_switches__([]).guest
      assert Escalated.Router.__route_switches__([]).widget
    end
  end

  describe "customer_middleware" do
    setup do
      Application.put_env(:escalated, :knowledge_base_enabled, true)

      router =
        router!(Escalated.RouteSwitchesTest.StaffOnly,
          customer_middleware: [Escalated.Plugs.EnsureAgent]
        )

      %{
        router: router,
        customer: host_user!(%{name: "Cy Customer"}),
        agent: host_user!(%{name: "Al Agent", is_agent: true})
      }
    end

    test "a signed-in user who fails the guard is refused on customer and KB routes", ctx do
      for {method, path} <- [
            {:get, "/support/tickets"},
            {:get, "/support/tickets/new"},
            {:post, "/support/tickets"},
            {:get, "/support/tickets/ESC-1"},
            {:post, "/support/tickets/ESC-1/reply"},
            {:post, "/support/tickets/ESC-1/rate"},
            {:get, "/support/kb"},
            {:get, "/support/kb/some-article"}
          ] do
        conn = EmbedHost.visit(ctx.router, method, path, ctx.customer, inertia: false)
        assert conn.status == 403, "#{method} #{path} answered #{conn.status}"
      end
    end

    test "a user who passes the guard reaches the pages", ctx do
      assert EmbedHost.visit(ctx.router, :get, "/support/tickets", ctx.agent).status == 200
      assert EmbedHost.visit(ctx.router, :get, "/support/kb", ctx.agent).status == 200
    end

    test "by default the same customer reaches the pages", ctx do
      router = Escalated.Test.Router
      assert EmbedHost.visit(router, :get, "/support/tickets", ctx.customer).status == 200
      assert EmbedHost.visit(router, :get, "/support/kb", ctx.customer).status == 200
    end

    test "a value that is not a plug or pipeline name is refused at compile time" do
      assert_raise ArgumentError, ~r/customer_middleware/, fn ->
        Escalated.Router.__route_switches__(customer_middleware: ["can:agent"])
      end
    end
  end
end
