defmodule Escalated.Controllers.Admin.DatabaseConnectionController do
  @moduledoc """
  A read-only status view of the database Escalated's own tables live on
  (`Escalated/Admin/Settings/DatabaseConnection`).

  In Ecto the repo is the connection, and the host picks it in config
  (`config :escalated, repo: MyApp.Repo`), so there is one connection to
  describe and it cannot be switched from the panel: `pinnedByConfig` is
  always true and `update` is refused. Laravel's runtime switch has no
  counterpart here.

  With tenancy enabled the screen is not served at all: the database is the
  platform's, Laravel shows it to platform admins only, and this package has
  no admin above a merchant's.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  plug :refuse_tenants

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.Ticket

  def index(conn, _params) do
    name = repo_name()

    UIRenderer.render_page(conn, "Escalated/Admin/Settings/DatabaseConnection", %{
      connections: [describe()],
      current: name,
      hostDefault: name,
      pinnedByConfig: true,
      tablePrefix: Escalated.config(:table_prefix, "escalated_")
    })
  end

  def test(conn, params) do
    case params["connection"] do
      name when is_binary(name) and name != "" ->
        if name == repo_name() do
          json(conn, describe())
        else
          FormResponse.invalid(
            conn,
            %{"connection" => ["[#{String.slice(name, 0, 64)}] is not a configured connection."]},
            index_path()
          )
        end

      _ ->
        FormResponse.invalid(
          conn,
          %{"connection" => ["The connection field is required."]},
          index_path()
        )
    end
  end

  def update(conn, _params) do
    conn
    |> put_flash(
      :error,
      "The database connection is set in configuration and cannot be changed from here."
    )
    |> redirect(to: index_path())
  end

  defp refuse_tenants(conn, _opts) do
    if Escalated.Tenancy.enabled?() do
      conn |> send_resp(404, "Not Found") |> halt()
    else
      conn
    end
  end

  defp repo_name, do: Escalated.storage_repo() |> inspect()

  # Never raises: a probe that fails reports the connection unreachable.
  defp describe do
    repo = Escalated.storage_repo()
    config = safe_config(repo)

    base = %{
      name: repo_name(),
      driver: driver(repo),
      database: label(repo, config),
      is_current: true,
      is_host_default: true,
      reachable: false,
      migrated: false,
      ticket_count: nil,
      error: nil
    }

    try do
      Ecto.Adapters.SQL.query!(repo, "SELECT 1", [])
      base = %{base | reachable: true}

      if tickets_table?(repo) do
        %{base | migrated: true, ticket_count: Escalated.repo().aggregate(Ticket, :count)}
      else
        base
      end
    rescue
      error -> %{base | error: Exception.message(error)}
    end
  end

  defp tickets_table?(repo) do
    table = Escalated.config(:table_prefix, "escalated_") <> "tickets"

    {sql, params} =
      case driver(repo) do
        "sqlite" ->
          {"SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?1", [table]}

        "postgres" ->
          {"SELECT count(*) FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = $1",
           [table]}

        "mysql" ->
          {"SELECT count(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?",
           [table]}

        _ ->
          {nil, nil}
      end

    case sql do
      nil ->
        false

      sql ->
        %{rows: [[count]]} = Ecto.Adapters.SQL.query!(repo, sql, params)
        count > 0
    end
  end

  defp safe_config(repo) do
    repo.config()
  rescue
    _ -> []
  end

  defp driver(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.SQLite3 -> "sqlite"
      Ecto.Adapters.Postgres -> "postgres"
      Ecto.Adapters.MyXQL -> "mysql"
      other -> other |> inspect() |> String.split(".") |> List.last() |> String.downcase()
    end
  end

  # No credentials: the database (path or name) and the host, nothing else.
  defp label(repo, config) do
    database = config[:database] && to_string(config[:database])
    host = config[:hostname] || config[:socket_dir] || config[:socket]

    cond do
      driver(repo) == "sqlite" -> database
      database && host -> "#{database} @ #{host}"
      database -> database
      true -> nil
    end
  end

  defp index_path,
    do: "#{Escalated.config(:route_prefix, "/support")}/admin/settings/database"
end
