defmodule Escalated.Rendering.UIRendererTest do
  use ExUnit.Case, async: true

  alias Escalated.Rendering.UIRenderer

  # The renderer decides between Inertia and JSON with Code.ensure_loaded?/1
  # guards, which means a wrong module name does not raise -- it silently falls
  # back to JSON and the panel renders nothing. These tests exist because that
  # failure mode is invisible otherwise.

  test "the Inertia adapter the renderer looks for is actually available" do
    assert Code.ensure_loaded?(Inertia),
           "the maintained adapter is the `inertia` package (module Inertia); " <>
             "`inertia_phoenix` is retired and pinned two CVEs"

    assert Code.ensure_loaded?(Inertia.Controller)
  end

  test "render_page/3 renders through Inertia rather than falling back to JSON" do
    conn = build_conn()

    rendered = UIRenderer.render_page(conn, "Tickets/Index", %{ticket_count: 3})

    # An Inertia XHR response carries the component and props in its payload.
    # The JSON fallback would carry only the bare props, with no component.
    assert rendered.status == 200
    body = Jason.decode!(rendered.resp_body)

    assert body["component"] == "Tickets/Index"
    assert body["props"]["ticket_count"] == 3
  end

  test "data shared by ShareInertiaData reaches the rendered page props" do
    # The old adapter read shared data out of conn.assigns; `inertia` reads it
    # from conn.private via assign_prop/3. Getting that wrong does not raise --
    # the page renders with the shared half of its props silently missing.
    rendered =
      build_conn()
      |> Plug.Conn.assign(:current_user, nil)
      |> Escalated.Plugs.ShareInertiaData.call([])
      |> UIRenderer.render_page("Tickets/Index", %{ticket_count: 3})

    props = Jason.decode!(rendered.resp_body)["props"]

    assert props["ticket_count"] == 3, "inline props must survive"
    assert is_map(props["escalated"]), "shared escalated props must survive"
    assert props["escalated"]["route_prefix"]
  end

  test "render_json/2 still renders bare props" do
    body =
      build_conn()
      |> UIRenderer.render_json(%{ticket_count: 3})
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()

    assert body == %{"ticket_count" => 3}
    refute Map.has_key?(body, "component")
  end

  # Inertia.Plug answers an XHR whose x-inertia-version does not match with a
  # 409 force-refresh, so the version has to be negotiated before the request
  # under test is built. Read it off a plain pass through the plug.
  defp build_conn do
    version =
      Plug.Test.conn(:get, "/escalated/tickets")
      |> Plug.Test.init_test_session(%{})
      |> Inertia.Plug.call(Inertia.Plug.init([]))
      |> Map.fetch!(:private)
      |> Map.fetch!(:inertia_version)

    Plug.Test.conn(:get, "/escalated/tickets")
    |> Plug.Test.init_test_session(%{})
    # `inertia` reads assigns.flash when building a response, so the host
    # pipeline must run fetch_flash before it. The retired adapter did not
    # require this.
    |> Phoenix.Controller.fetch_flash()
    |> Plug.Conn.put_req_header("x-inertia", "true")
    |> Plug.Conn.put_req_header("x-inertia-version", to_string(version))
    |> Inertia.Plug.call(Inertia.Plug.init([]))
  end
end
