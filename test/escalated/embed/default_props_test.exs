defmodule Escalated.Embed.DefaultPropsTest do
  @moduledoc """
  With no embed configuration (the default) the admin pages are served where
  they always were, with no `embed` or `navigation` props and no framing
  headers (ADR 2026-11-05-embeddable-admin). The route table is compared in
  Escalated.Embed.DefaultUnchangedTest.
  """
  use Escalated.PageCase

  alias Escalated.Test.SharedPropsRouter

  setup do
    Application.delete_env(:escalated, :ui)
    %{admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})}
  end

  defp visit_shared(path, user) do
    conn(:get, path)
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> SharedPropsRouter.call(SharedPropsRouter.init([]))
  end

  test "the admin answers at {prefix}/admin with no embed or navigation props", ctx do
    conn = visit_shared("/support/admin/tags", ctx.admin)
    props = page!(conn, "Escalated/Admin/Tags/Index")

    refute Map.has_key?(props["escalated"], "embed")
    refute Map.has_key?(props["escalated"], "navigation")
    assert props["ziggy"]["routes"]["escalated.admin.tags.index"]["uri"] == "support/admin/tags"
    assert get_resp_header(conn, "content-security-policy") == []
    assert get_resp_header(conn, "x-frame-options") == []
  end

  test "redirects keep the standalone admin", ctx do
    conn =
      visit(:post, "/support/admin/tags", ctx.admin, %{tag: %{name: "Billing", slug: "billing"}})

    assert location(conn) == "/support/admin/tags"
  end

  test "admin_navigation/2 works without embedding, pointing at the standalone admin", ctx do
    items = Escalated.admin_navigation(ctx.admin, nil)
    tags = Enum.find(items, &(&1.key == "tags"))

    assert tags.url == "/support/admin/tags"
    assert tags.active == false
    refute Escalated.Embed.enabled?()
    assert Escalated.Embed.admin_base() == "/support/admin"
  end
end
