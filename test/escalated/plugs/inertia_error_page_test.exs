defmodule Escalated.Test.ErrorPage.ErrorJSON do
  @moduledoc false
  def render(template, _assigns),
    do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
end

defmodule Escalated.Test.ErrorPage.ProbeController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  def status(conn, %{"status" => status}) do
    conn
    |> put_status(String.to_integer(status))
    |> json(%{error: "upstream detail"})
  end

  def raise_error(_conn, _params), do: raise("relation escalated_secret_table does not exist")
end

defmodule Escalated.Test.ErrorPage.Router do
  @moduledoc false
  # The package's routes, plus stand-ins for failures the suite cannot
  # otherwise provoke on a real route, behind the same plug, and a host route.
  use Phoenix.Router
  use Escalated.Router

  pipeline :browser do
    plug :fetch_session
    plug :fetch_flash
    plug Inertia.Plug
  end

  scope "/" do
    pipe_through :browser
    escalated_routes("/support", api: true)
  end

  scope "/support/probe", Escalated.Test.ErrorPage do
    pipe_through [:browser, Escalated.Plugs.InertiaErrorPage]
    get "/raise", ProbeController, :raise_error
    get "/:status", ProbeController, :status
  end

  scope "/host", Escalated.Test.ErrorPage do
    pipe_through :browser
    get "/:status", ProbeController, :status
  end
end

defmodule Escalated.Test.ErrorPage.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :escalated
  plug Plug.Session, store: :cookie, key: "_esc_error_page", signing_salt: "errorpage"
  plug Escalated.Test.ErrorPage.Router
end

defmodule Escalated.Test.ErrorPage.DebugEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :escalated
  plug Plug.Session, store: :cookie, key: "_esc_error_page", signing_salt: "errorpage"
  plug Escalated.Test.ErrorPage.Router
end

defmodule Escalated.Plugs.InertiaErrorPageTest do
  @moduledoc """
  A refusal or a failure inside the panel stays inside the panel.

  An Inertia visit that gets a JSON error or an HTML error page back has
  nowhere to put it: the client opens it in a modal over the screen the user
  was on. So an Inertia visit to one of Escalated's routes that ends in 403,
  404, 419, 429, 500 or 503 gets the shared frontend's Escalated/Error page,
  with the props Rails and Laravel send: the status and a generic message.
  Full page loads, JSON clients and the host's own routes are left alone.
  """
  use Escalated.PageCase

  import Phoenix.ConnTest, only: [assert_error_sent: 2]

  alias Escalated.Test.ErrorPage.{DebugEndpoint, Endpoint, ErrorJSON}

  @secret String.duplicate("a", 64)

  setup_all do
    for {endpoint, debug} <- [{Endpoint, false}, {DebugEndpoint, true}] do
      Application.put_env(:escalated, endpoint,
        secret_key_base: @secret,
        render_errors: [formats: [json: ErrorJSON], layout: false],
        debug_errors: debug,
        server: false
      )

      start_supervised!(endpoint)
    end

    :ok
  end

  defp request(path, opts \\ []) do
    conn =
      conn(:get, path)
      |> then(fn conn ->
        if opts[:user], do: assign(conn, :current_user, opts[:user]), else: conn
      end)

    conn =
      Enum.reduce(opts[:headers] || inertia_headers(), conn, fn {k, v}, conn ->
        put_req_header(conn, k, v)
      end)

    (opts[:endpoint] || Endpoint).call(conn, [])
  end

  defp inertia_headers, do: [{"x-inertia", "true"}, {"x-inertia-version", inertia_version()}]

  defp assert_error_page(conn, status, message) do
    assert conn.status == status
    assert get_resp_header(conn, "x-inertia") == ["true"]
    page = Jason.decode!(conn.resp_body)
    assert page["component"] == "Escalated/Error"
    assert page["props"] == %{"status" => status, "message" => message}
    page
  end

  test "an Inertia visit refused by the admin gate gets the Error page" do
    agent = host_user!(%{is_agent: true})

    conn = request("/support/admin/settings", user: agent)

    assert_error_page(conn, 403, "You are not authorized to perform this action.")
    refute conn.resp_body =~ "Admin access required"
  end

  test "an Inertia visit to a missing ticket gets the Error page" do
    agent = host_user!(%{is_agent: true})

    conn = request("/support/agent/tickets/NOPE-404", user: agent)

    page = assert_error_page(conn, 404, "The requested resource was not found.")
    assert page["url"] == "/support/agent/tickets/NOPE-404"
    refute conn.resp_body =~ "Ticket not found"
  end

  for {status, message} <- [
        {419, "Your session has expired. Refresh the page and try again."},
        {429, "Too many requests. Wait a moment and try again."},
        {503, "The service is temporarily unavailable. Try again shortly."}
      ] do
    test "an Inertia visit answered with #{status} gets the Error page" do
      conn = request("/support/probe/#{unquote(status)}")

      assert_error_page(conn, unquote(status), unquote(message))
      refute conn.resp_body =~ "upstream detail"
    end
  end

  test "an exception on an Inertia visit gets the Error page, without its message" do
    {500, headers, body} =
      assert_error_sent(500, fn -> request("/support/probe/raise") end)

    assert {"x-inertia", "true"} in headers
    page = Jason.decode!(body)
    assert page["component"] == "Escalated/Error"
    assert page["props"] == %{"status" => 500, "message" => "Something went wrong on our end."}
    refute body =~ "escalated_secret_table"
  end

  test "leaves a 500 to the debug page while debug_errors is on" do
    {500, headers, body} =
      assert_error_sent(500, fn -> request("/support/probe/raise", endpoint: DebugEndpoint) end)

    refute {"x-inertia", "true"} in headers
    refute body =~ "Escalated/Error"
  end

  test "leaves statuses the page has no wording for alone" do
    conn = request("/support/probe/422")

    assert conn.status == 422
    assert Jason.decode!(conn.resp_body) == %{"error" => "upstream detail"}
  end

  test "leaves a full page load alone" do
    agent = host_user!(%{is_agent: true})

    conn = request("/support/admin/settings", user: agent, headers: [])

    assert conn.status == 403
    assert get_resp_header(conn, "x-inertia") == []
    refute conn.resp_body =~ "Escalated/Error"
  end

  test "leaves a JSON request alone" do
    agent = host_user!(%{is_agent: true})

    conn =
      request("/support/admin/settings",
        user: agent,
        headers: [{"accept", "application/json"}]
      )

    assert conn.status == 403
    assert Jason.decode!(conn.resp_body) == %{"error" => "Admin access required"}
  end

  test "leaves a host route alone" do
    conn = request("/host/404")

    assert conn.status == 404
    assert Jason.decode!(conn.resp_body) == %{"error" => "upstream detail"}
  end

  test "leaves the JSON API alone, even with the Inertia header" do
    conn = request("/support/api/v1/tickets")

    assert conn.status == 401
    refute conn.resp_body =~ "Escalated/Error"

    conn = request("/support/api/v1/tickets/NOPE", headers: inertia_headers())
    refute conn.resp_body =~ "Escalated/Error"
  end

  test "stays off while the UI is disabled" do
    Application.put_env(:escalated, :ui_enabled, false)
    on_exit(fn -> Application.delete_env(:escalated, :ui_enabled) end)

    conn = request("/support/probe/503")

    assert conn.status == 503
    assert get_resp_header(conn, "x-inertia") == []
  end
end
