defmodule Escalated.Controllers.Admin.UserController do
  @moduledoc """
  Admin surface for the host User schema: list users with their
  `is_admin` / `is_agent` flags and grant or revoke either role.

  Mirrors `escalated-laravel` `Admin\\UserController`. The default
  installation pins on the host `users` table having `is_admin` and
  `is_agent` boolean columns — hosts using a different role system
  (Pow, Spatie-style, custom join table) should override this
  controller in their own router.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Rendering.UIRenderer

  @page_size 20

  @doc """
  GET /support/admin/users — paginated list of host users, ordered with
  admins first, then agents, then everyone else.
  """
  def index(conn, params) do
    repo = Escalated.repo()
    user_schema = Escalated.user_schema()

    search = params |> Map.get("search", "") |> to_string() |> String.trim()
    page = parse_page(Map.get(params, "page"))

    base_query = from(u in user_schema)
    filtered_query = apply_search(base_query, user_schema, search)

    total = repo.aggregate(filtered_query, :count, :id)

    rows =
      filtered_query
      |> order_by([u], desc: u.is_admin, desc: u.is_agent, asc: u.id)
      |> limit(^@page_size)
      |> offset(^((page - 1) * @page_size))
      |> repo.all()

    UIRenderer.render_page(conn, "Escalated/Admin/Users/Index", %{
      users: paginate(rows, page, total, search),
      filters: %{search: search},
      currentUserId: current_user_id(conn)
    })
  end

  @doc """
  PATCH /support/admin/users/:user_id/role — grant or revoke admin/agent
  on a single user. Body: `{role: "admin"|"agent", value: boolean}`.

  Safety: an admin cannot revoke their own admin role through this
  endpoint (would lock themselves out of the panel they're using).
  """
  def update_role(conn, %{"user_id" => user_id} = params) do
    with {:ok, role} <- validate_role(Map.get(params, "role")),
         {:ok, value} <- validate_value(Map.get(params, "value")) do
      apply_role_change(conn, user_id, role, value)
    else
      {:error, message} ->
        conn
        |> put_status(422)
        |> Phoenix.Controller.json(%{error: message})
    end
  end

  defp apply_role_change(conn, user_id, role, value) do
    repo = Escalated.repo()
    user_schema = Escalated.user_schema()

    case repo.get(user_schema, user_id) do
      nil ->
        conn
        |> put_status(404)
        |> Phoenix.Controller.json(%{error: "User not found"})

      target ->
        if role == "admin" and value == false and self_target?(conn, target) do
          conn
          |> put_flash(:error, "You cannot remove your own admin role.")
          |> redirect_back()
        else
          updates = build_updates(role, value, target)

          target
          |> Ecto.Changeset.change(updates)
          |> repo.update!()

          conn
          |> put_flash(:info, "User updated.")
          |> redirect_back()
        end
    end
  end

  # --- query helpers ---

  defp apply_search(query, _schema, ""), do: query

  defp apply_search(query, schema, term) do
    pattern = "%" <> term <> "%"
    has_name? = schema_has_field?(schema, :name)

    if has_name? do
      from(u in query,
        where: ilike(u.email, ^pattern) or ilike(u.name, ^pattern)
      )
    else
      from(u in query, where: ilike(u.email, ^pattern))
    end
  end

  defp schema_has_field?(schema, field) do
    schema.__schema__(:fields)
    |> Enum.member?(field)
  rescue
    _ -> true
  end

  defp paginate(rows, page, total, search) do
    last_page = max(div(total + @page_size - 1, @page_size), 1)

    %{
      data: Enum.map(rows, &user_to_payload/1),
      current_page: page,
      per_page: @page_size,
      total: total,
      last_page: last_page,
      from: if(total == 0, do: nil, else: (page - 1) * @page_size + 1),
      to: if(total == 0, do: nil, else: min(page * @page_size, total)),
      links: build_links(page, last_page, search)
    }
  end

  defp build_links(page, last_page, search) do
    prefix = Escalated.config(:route_prefix, "/support")
    base = "#{prefix}/admin/users"

    query_for = fn p ->
      params = if search == "", do: %{page: p}, else: %{page: p, search: search}
      base <> "?" <> URI.encode_query(params)
    end

    %{
      first: query_for.(1),
      last: query_for.(last_page),
      prev: if(page > 1, do: query_for.(page - 1), else: nil),
      next: if(page < last_page, do: query_for.(page + 1), else: nil)
    }
  end

  @doc false
  @spec user_to_payload(map()) :: map()
  def user_to_payload(user) do
    %{
      id: Map.get(user, :id),
      name: Map.get(user, :name),
      email: Map.get(user, :email),
      is_admin: !!Map.get(user, :is_admin, false),
      is_agent: !!Map.get(user, :is_agent, false)
    }
  end

  @doc false
  @spec build_updates(String.t(), boolean(), map()) :: Keyword.t()
  def build_updates("admin", true, _target), do: [is_admin: true, is_agent: true]
  def build_updates("admin", false, _target), do: [is_admin: false]

  def build_updates("agent", true, _target), do: [is_agent: true]

  def build_updates("agent", false, target) do
    if Map.get(target, :is_admin, false) do
      # Revoking agent from an admin would leave the admin gate on
      # but the agent gate off — confusing. Demote them fully.
      [is_agent: false, is_admin: false]
    else
      [is_agent: false]
    end
  end

  # --- input validation ---

  @doc false
  @spec validate_role(any()) :: {:ok, String.t()} | {:error, String.t()}
  def validate_role(role) when role in ["admin", "agent"], do: {:ok, role}
  def validate_role(_), do: {:error, "role must be 'admin' or 'agent'"}

  @doc false
  @spec validate_value(any()) :: {:ok, boolean()} | {:error, String.t()}
  def validate_value(value) when is_boolean(value), do: {:ok, value}
  def validate_value("true"), do: {:ok, true}
  def validate_value("false"), do: {:ok, false}
  def validate_value(1), do: {:ok, true}
  def validate_value(0), do: {:ok, false}
  def validate_value(_), do: {:error, "value must be a boolean"}

  defp parse_page(nil), do: 1
  defp parse_page(p) when is_integer(p) and p > 0, do: p

  defp parse_page(p) when is_binary(p) do
    case Integer.parse(p) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  # --- conn helpers ---

  defp self_target?(conn, target) do
    case current_user_id(conn) do
      nil -> false
      id -> to_string(id) == to_string(Map.get(target, :id))
    end
  end

  defp current_user_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp redirect_back(conn) do
    target =
      case get_req_header(conn, "referer") do
        [ref | _] -> ref
        _ -> admin_users_path()
      end

    redirect(conn, to: target)
  end

  defp admin_users_path do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/users"
  end
end
