defmodule Escalated.Controllers.Admin.DepartmentController do
  @moduledoc """
  Admin controller for managing departments.

  The shared `Escalated/Admin/Departments/Form` posts its fields flat
  (`name`, `slug`, ..., `business_schedule_id`); the older nested
  `%{"department" => ...}` body still works. The form gets the business
  schedules to pick from as `schedules`, as escalated-laravel's
  `DepartmentController` passes them. `business_schedule_id` changes only when
  sent, and an id that names no schedule is a field error.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{BusinessSchedule, Department}

  @fields ~w(name slug description email is_active default_sla_policy_id business_schedule_id)

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
        UIRenderer.render_page(conn, "Escalated/Admin/Departments/Form", %{
          department: department_json(dept),
          schedules: BusinessSchedule.options()
        })
    end
  end

  # GET /departments/:id/edit (escalated.admin.departments.edit, which the
  # shared Index links to) renders the same form as show.
  def edit(conn, params), do: show(conn, params)

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Departments/Form", %{
      schedules: BusinessSchedule.options()
    })
  end

  def create(conn, params) do
    repo = Escalated.repo()
    params = form_params(params)

    %Department{}
    |> Department.changeset(params)
    |> BusinessSchedule.validate_reference()
    |> repo.insert()
    |> case do
      {:ok, dept} ->
        conn
        |> put_flash(:info, "Department created.")
        |> redirect(to: admin_department_path(conn, dept))

      {:error, changeset} ->
        if FormResponse.inertia?(conn) do
          FormResponse.invalid(conn, changeset, admin_departments_path(conn) <> "/new")
        else
          conn
          |> put_status(422)
          |> UIRenderer.render_page("Escalated/Admin/Departments/Form", %{
            errors: format_errors(changeset),
            department: params
          })
        end
    end
  end

  def update(conn, %{"id" => id} = params) do
    repo = Escalated.repo()
    params = form_params(params)

    case repo.get(Department, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Department not found"})

      dept ->
        dept
        |> Department.changeset(params)
        |> BusinessSchedule.validate_reference()
        |> repo.update()
        |> case do
          {:ok, updated} ->
            conn
            |> put_flash(:info, "Department updated.")
            |> redirect(to: admin_department_path(conn, updated))

          {:error, changeset} ->
            if FormResponse.inertia?(conn) do
              FormResponse.invalid(conn, changeset, "#{admin_department_path(conn, dept)}/edit")
            else
              conn
              |> put_status(422)
              |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
            end
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

  # The shared form's flat fields, or the older nested `department` body.
  defp form_params(%{"department" => nested}) when is_map(nested), do: Map.take(nested, @fields)
  defp form_params(params), do: Map.take(params, @fields)

  defp department_json(dept) do
    %{
      id: dept.id,
      name: dept.name,
      slug: dept.slug,
      description: dept.description,
      email: dept.email,
      is_active: dept.is_active,
      default_sla_policy_id: dept.default_sla_policy_id,
      business_schedule_id: dept.business_schedule_id
    }
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
