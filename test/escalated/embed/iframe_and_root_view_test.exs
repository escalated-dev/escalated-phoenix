defmodule Escalated.Embed.IframeAndRootViewTest do
  @moduledoc """
  The per-request embed settings (ADR 2026-11-05-embeddable-admin): iframe
  mode's framing headers and the `root_view` layout, each on embedded admin
  responses only.
  """
  use Escalated.PageCase

  alias Escalated.Test.EmbedHost

  @router Escalated.Test.EmbedLayoutRouter

  setup_all do
    EmbedHost.router!(@router, EmbedHost.base())
    :ok
  end

  setup do
    on_exit(&EmbedHost.clear_embed/0)
    %{admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})}
  end

  defp host_visit(method, path, user, opts \\ []),
    do: EmbedHost.visit(@router, method, path, user, opts)

  describe "iframe mode" do
    setup do
      EmbedHost.put_embed(
        mode: :iframe,
        frame_ancestors: [
          "https://allowed.example",
          "*",
          "https://*.example.com",
          "https://other.example/path",
          "ftp://files.example",
          "https://allowed.example"
        ]
      )

      :ok
    end

    test "an embedded response may be framed by the listed origins only", ctx do
      conn = host_visit(:get, "/admin/support/tags", ctx.admin)
      page!(conn, "Escalated/Admin/Tags/Index")

      policies = get_resp_header(conn, "content-security-policy")
      assert "frame-ancestors 'self' https://allowed.example" in policies
      # The host's own policy (put_secure_browser_headers) is kept.
      assert length(policies) == 2
      # Set by the host's pipeline and by a host before_send callback; gone.
      assert get_resp_header(conn, "x-frame-options") == []
    end

    test "every other response is left alone", ctx do
      conn = host_visit(:get, "/support/agent/tickets", ctx.admin)
      page!(conn, "Escalated/Agent/TicketIndex")

      assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]

      refute "frame-ancestors 'self' https://allowed.example" in get_resp_header(
               conn,
               "content-security-policy"
             )
    end

    test "a refusal inside the frame is framable too", ctx do
      conn = host_visit(:get, "/admin/support/tags", ctx.admin, headers: [{"x-host-deny", "1"}])
      assert conn.status == 403
      assert get_resp_header(conn, "x-frame-options") == []
    end

    test "the prop carries the mode and the allow-list", ctx do
      props =
        host_visit(:get, "/admin/support/tags", ctx.admin) |> page!("Escalated/Admin/Tags/Index")

      assert props["escalated"]["embed"]["mode"] == "iframe"
      assert props["escalated"]["embed"]["allowed_origins"] == ["https://allowed.example"]
    end

    test "no allow-list means 'self' only", ctx do
      EmbedHost.put_embed(mode: :iframe, frame_ancestors: [])
      conn = host_visit(:get, "/admin/support/tags", ctx.admin)
      assert "frame-ancestors 'self'" in get_resp_header(conn, "content-security-policy")
    end

    test "accepts the comma-separated environment form", ctx do
      EmbedHost.put_embed(
        mode: "iframe",
        frame_ancestors: "https://a.example, https://B.example:8443 ,*"
      )

      conn = host_visit(:get, "/admin/support/tags", ctx.admin)

      assert "frame-ancestors 'self' https://a.example https://b.example:8443" in get_resp_header(
               conn,
               "content-security-policy"
             )
    end
  end

  describe "root_view" do
    setup do
      EmbedHost.put_embed(root_view: {Escalated.Test.EmbedHost.Layouts, :escalated_admin})
      :ok
    end

    test "renders an embedded page's first load in the host's admin layout, with the menu", ctx do
      conn = host_visit(:get, "/admin/support/tags", ctx.admin, inertia: false)
      assert conn.status == 200
      body = conn.resp_body

      assert body =~ ~s(<header id="host-admin-header">Host admin</header>)
      assert body =~ ~s(<main id="host-admin-main">)
      assert body =~ "Escalated/Admin/Tags/Index"

      assert body =~
               ~r{<a href="/admin/support/tags" class="active" aria-current="page">\s*Tags\s*</a>}

      assert body =~ ~r{<a href="/admin/support/settings" class="">\s*Settings\s*</a>}
      refute body =~ ~s(id="host-root")
    end

    test "leaves every other page on the host's root layout", ctx do
      conn = host_visit(:get, "/support/agent/tickets", ctx.admin, inertia: false)
      assert conn.status == 200
      assert conn.resp_body =~ ~s(<main id="host-root">)
      refute conn.resp_body =~ "host-admin-header"
    end

    test "adds no framing header in layout mode", ctx do
      conn = host_visit(:get, "/admin/support/tags", ctx.admin, inertia: false)
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    end
  end
end
