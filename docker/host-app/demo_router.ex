defmodule EscalatedDemoWeb.Router do
  use EscalatedDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", EscalatedDemoWeb do
    pipe_through :api
  end

  scope "/", EscalatedDemoWeb do
    pipe_through :browser

    get "/", DemoController, :picker
    get "/demo", DemoController, :picker
    get "/demo/login/:id", DemoController, :login
    get "/demo/agent/:id", DemoController, :agent
  end
end

defmodule EscalatedDemoWeb.DemoController do
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Schemas.{AgentProfile, Department}

  def picker(conn, _params) do
    ensure_seeded()
    repo = Escalated.repo()
    agents = repo.all(AgentProfile)

    rows =
      Enum.map_join(agents, "", fn a ->
        ~s|<a class='user' href='/demo/login/#{a.id}'>
          <span>#{escape(a.display_name)}</span>
          <span class='meta'>#{a.role} · UserId #{a.user_id}</span>
        </a>|
      end)

    body = """
    <!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>
    <title>Escalated · Phoenix Demo</title><style>#{styles()}</style></head>
    <body><div class='wrap'>
      <h1>Escalated Phoenix Demo</h1>
      <p class='lede'>Click an agent to load their profile. DB seeds on first request.</p>
      #{rows}
    </div></body></html>
    """

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body)
  end

  def login(conn, %{"id" => id}) do
    Phoenix.Controller.redirect(conn, to: "/demo/agent/#{id}")
  end

  def agent(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(AgentProfile, id) do
      nil ->
        Plug.Conn.send_resp(conn, 404, "Agent not found")

      a ->
        dept_count = repo.aggregate(Department, :count)

        body = """
        <!DOCTYPE html><html lang='en'><head><meta charset='utf-8'>
        <title>Agent #{escape(a.display_name)}</title><style>#{styles()}</style></head>
        <body><div class='wrap'>
          <h1>Logged in as #{escape(a.display_name)}</h1>
          <p class='meta'>Role: #{a.role} · UserId: #{a.user_id} · Active: #{a.is_active}</p>
          <p>Phoenix host + Postgres + Ecto round-trip verified end-to-end.
             Department count: #{dept_count}.
             <a href='/demo'>Back to picker</a>.</p>
        </div></body></html>
        """

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, body)
    end
  end

  defp ensure_seeded do
    repo = Escalated.repo()

    if repo.aggregate(AgentProfile, :count) == 0 do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Enum.each(
        [
          %{name: "Support", slug: "support"},
          %{name: "Billing", slug: "billing"}
        ],
        fn d ->
          %Department{}
          |> Ecto.Changeset.change(%{
            name: d.name,
            slug: d.slug,
            is_active: true,
            inserted_at: now,
            updated_at: now
          })
          |> repo.insert()
        end
      )

      Enum.each(
        [
          {1, "Alice (Admin)", "admin"},
          {2, "Bob (Agent)", "agent"},
          {3, "Carol (Agent)", "agent"}
        ],
        fn {uid, name, role} ->
          %AgentProfile{}
          |> Ecto.Changeset.change(%{
            user_id: uid,
            display_name: name,
            role: role,
            is_active: true,
            max_tickets: 50,
            metadata: %{},
            inserted_at: now,
            updated_at: now
          })
          |> repo.insert()
        end
      )
    end
  end

  defp styles do
    """
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0f172a;color:#e2e8f0;margin:0;padding:2rem}
    .wrap{max-width:720px;margin:0 auto}
    h1{font-size:1.5rem;margin:0 0 .25rem}
    p.lede{color:#94a3b8;margin:0 0 2rem}
    p.meta{color:#94a3b8;font-size:.85rem;margin-bottom:1rem}
    a.user{display:flex;width:100%;align-items:center;justify-content:space-between;padding:.75rem 1rem;background:#1e293b;border:1px solid #334155;border-radius:8px;color:#f1f5f9;font-size:.95rem;text-decoration:none;cursor:pointer;margin-bottom:.5rem;text-align:left;box-sizing:border-box}
    a.user:hover{background:#273549;border-color:#475569}
    .meta{color:#94a3b8;font-size:.8rem}
    a{color:#60a5fa}
    """
  end

  defp escape(nil), do: ""
  defp escape(s), do: s |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
