defmodule Escalated.Test.InertiaHost.Layouts do
  @moduledoc false
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html>
      <head><title>Inertia host contract</title></head>
      <body><main id="host-shell">{@inner_content}</main></body>
    </html>
    """
  end
end

defmodule Escalated.Test.InertiaHost.Controller do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Plugs.ShareInertiaData
  alias Escalated.Rendering.UIRenderer

  def page(conn, params) do
    conn
    |> assign(:current_user, %{id: 42, name: "Fixture User", email: "fixture@example.test"})
    |> assign(:fixture_csp_nonce, "fixture-nonce")
    |> put_root_layout({Escalated.Test.InertiaHost.Layouts, :root})
    |> put_layout(false)
    |> ShareInertiaData.call([])
    |> UIRenderer.render_page("Escalated/Customer/Index", %{
      title: "Fixture page",
      payload: params["payload"] || "fixture value"
    })
  end

  def redirect_page(conn, _params) do
    conn
    |> put_flash(:notice, "Fixture saved")
    |> redirect(to: "/fixture/page")
  end
end

defmodule Escalated.Test.InertiaHost.Router do
  @moduledoc false
  use Phoenix.Router
  import Phoenix.Controller

  pipeline :browser do
    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: ["*/*"],
      json_decoder: Jason

    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :accepts, ["html", "json"]
    plug Inertia.Plug
  end

  scope "/fixture", Escalated.Test.InertiaHost do
    pipe_through :browser
    get "/page", Controller, :page
    post "/redirect", Controller, :redirect_page
    put "/redirect", Controller, :redirect_page
  end
end
