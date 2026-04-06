defmodule Escalated.Controllers.Admin.DepartmentController do
  @moduledoc """
  Admin controller for managing departments.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Schemas.Department
  alias Escalated.Rendering.UIRenderer

  def index(conn, _params) do
    repo = Escalated.repo()
    departments = repo.all(Department.ordered())

    UIRenderer.render_page(conn, "Escalated/Admin/Departments/Index", %{
      departments:
        Enum.map(departments, fn d ->
          %{
            id: d.id,
            name: d.name,
            slug: d.slug,
            description: d.description,
            email: d.email,
            is_active: d.is_active,
            default_sla_policy_id: d.default_sla_policy_id
          }
        end)
    })
  end

  def show(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Department, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Department not found"})

      dept ->
        UIRenderer.render_page(conn, "Escalated/Admin/Departments/Show", %{
          department: %{
            id: dept.id,
            name: dept.name,
            slug: dept.slug,
            description: dept.description,
            email: dept.email,
            is_active: dept.is_active,
            default_sla_policy_id: dept.default_sla_policy_id
          }
        })
    end
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Departments/New", %{})
  end

  def create(conn, %{"department" => params}) do
    repo = Escalated.repo()

    %Department{}
    |> Department.changeset(params)
    |> repo.insert()
    |> case do
      {:ok, dept} ->
        conn
        |> put_flash(:info, "Department created.")
        |> redirect(to: admin_department_path(conn, dept))

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> UIRenderer.render_page("Escalated/Admin/Departments/New", %{
          errors: format_errors(changeset),
          department: params
        })
    end
  end

  def update(conn, %{"id" => id, "department" => params}) do
    repo = Escalated.repo()

    case repo.get(Department, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Department not found"})

      dept ->
        dept
        |> Department.changeset(params)
        |> repo.update()
        |> case do
          {:ok, updated} ->
            conn
            |> put_flash(:info, "Department updated.")
            |> redirect(to: admin_department_path(conn, updated))

          {:error, changeset} ->
            conn
            |> put_status(422)
            |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Department, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Department not found"})

      dept ->
        repo.delete(dept)

        conn
        |> put_flash(:info, "Department deleted.")
        |> redirect(to: admin_departments_path(conn))
    end
  end

  defp admin_department_path(conn, dept) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/departments/#{dept.id}"
  end

  defp admin_departments_path(conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/departments"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
