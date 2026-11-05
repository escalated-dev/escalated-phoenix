defmodule Escalated.Embed.HostGateTest do
  @moduledoc """
  `replace_admin_gate: true` (ADR 2026-11-05-embeddable-admin): the host's
  middleware alone decides who reaches the embedded admin. Two-factor and
  route permissions still apply, and nothing outside the embedded admin loses
  Escalated's gates.
  """
  use Escalated.PageCase

  alias Escalated.Test.EmbedHost

  @router Escalated.Test.EmbedHostGateRouter
  @host "www.example.com"

  setup_all do
    EmbedHost.router!(@router, Keyword.put(EmbedHost.base(), :replace_admin_gate, true))
    :ok
  end

  setup do
    EmbedHost.put_embed(replace_admin_gate: true)

    on_exit(fn ->
      EmbedHost.clear_embed()
      Application.delete_env(:escalated, :access)
    end)

    %{
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      agent: host_user!(%{name: "Al Agent", is_agent: true}),
      customer: host_user!(%{name: "Cy Customer"})
    }
  end

  defp host_visit(method, path, user, opts \\ []),
    do: EmbedHost.visit(@router, method, path, user, opts)

  test "drops only Escalated's admin gate from the embedded routes" do
    pipes =
      @router.__route_table__()
      |> Enum.find(&(&1.path == "/admin/support/tags" and &1.verb == :get))
      |> Map.fetch!(:pipe_through)

    refute Escalated.Plugs.EnsureAdmin in pipes
    assert Escalated.Plugs.RequireTwoFactor in pipes
    assert Escalated.Plugs.EnforceRoutePermissions in pipes
    assert :host_admin in pipes

    agent_pipes =
      @router.__route_table__()
      |> Enum.find(&(&1.path == "/support/agent/tickets" and &1.verb == :get))
      |> Map.fetch!(:pipe_through)

    assert Escalated.Plugs.EnsureAgent in agent_pipes
  end

  test "a user the host lets through reaches the admin, admin or not", ctx do
    conn = host_visit(:get, "/admin/support/tags", ctx.agent)
    page!(conn, "Escalated/Admin/Tags/Index")
    assert get_resp_header(conn, "x-host-admin") == ["1"]
  end

  test "the host refuses an Escalated admin and that is final", ctx do
    conn = host_visit(:get, "/admin/support/tags", ctx.admin, headers: [{"x-host-deny", "1"}])
    assert conn.status == 403
  end

  test "route permissions still apply", ctx do
    {:ok, _} = Escalated.Tenancy.Provisioner.seed()
    Application.put_env(:escalated, :access, roles_permissions: true)

    assert host_visit(:get, "/admin/support/tags", ctx.agent).status == 403
  end

  test "the agent panel keeps Escalated's gates", ctx do
    assert host_visit(:get, "/support/agent/tickets", ctx.customer).status == 403
  end

  test "the navigation is built for any signed-in user", ctx do
    keys = Escalated.admin_navigation(ctx.agent, nil) |> Enum.map(& &1.key)
    assert "tags" in keys
    assert Escalated.admin_navigation(nil, nil) == []
  end

  test "the standalone URL is not routed" do
    assert Phoenix.Router.route_info(@router, "GET", "/support/admin/tags", @host) == :error
  end
end
