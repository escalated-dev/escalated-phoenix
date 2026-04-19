defmodule EscalatedDemoWeb.Router do
  use EscalatedDemoWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", EscalatedDemoWeb do
    pipe_through :api
  end

  scope "/" do
    get "/demo", EscalatedDemoWeb.DemoController, :index
    get "/", EscalatedDemoWeb.DemoController, :index
  end
end

defmodule EscalatedDemoWeb.DemoController do
  use Phoenix.Controller, formats: [:html, :json]

  def index(conn, _params) do
    body = """
    <html><body><h1>Escalated Phoenix Demo</h1>
    <p>Host project bootstrapped. Picker UI + click-to-login + seed are
    a follow-up — see PR body. The package compiles and the host serves
    requests on Postgres + Mailpit.</p></body></html>
    """

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body)
  end
end
