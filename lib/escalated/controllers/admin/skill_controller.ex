defmodule Escalated.Controllers.Admin.SkillController do
  @moduledoc """
  Admin CRUD for skills, routing mappings, and per-agent proficiency.

  Wire contract: escalated-developer-context/domain-model/skills-management.md
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Skills

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Skills/Index", %{
      skills: Skills.list_for_admin()
    })
  end

  def new(conn, _params) do
    Skills.form_context()
    |> Map.put(:skill, nil)
    |> then(&UIRenderer.render_page(conn, "Escalated/Admin/Skills/Form", &1))
  end

  def create(conn, params) do
    case Skills.create_skill(skill_params(params)) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Skill created.")
        |> redirect(to: admin_skills_path(conn))

      {:error, %Ecto.Changeset{} = cs} ->
        ctx =
          Skills.form_context()
          |> Map.put(:skill, nil)
          |> Map.put(:errors, format_errors(cs))

        conn
        |> put_status(422)
        |> UIRenderer.render_page("Escalated/Admin/Skills/Form", ctx)

      {:error, _} ->
        conn
        |> put_status(422)
        |> Phoenix.Controller.json(%{error: "Could not save skill"})
    end
  end

  def edit(conn, %{"id" => id}) do
    case Skills.find_for_edit(id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Skill not found"})

      skill ->
        Skills.form_context()
        |> Map.put(:skill, skill)
        |> then(&UIRenderer.render_page(conn, "Escalated/Admin/Skills/Form", &1))
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Skills.update_skill(id, skill_params(params)) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Skill updated.")
        |> redirect(to: admin_skills_path(conn))

      {:error, :not_found} ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Skill not found"})

      {:error, %Ecto.Changeset{} = cs} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})

      {:error, _} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{error: "Could not save skill"})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Skills.delete_skill(id) do
      {:error, :not_found} ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Skill not found"})

      {:ok, _} ->
        conn
        |> put_flash(:info, "Skill deleted.")
        |> redirect(to: admin_skills_path(conn))

      {:error, %Ecto.Changeset{}} ->
        conn
        |> put_status(422)
        |> Phoenix.Controller.json(%{error: "Could not delete skill"})
    end
  end

  defp skill_params(params) when is_map(params) do
    base =
      case params do
        %{"skill" => nested} when is_map(nested) -> nested
        other -> other
      end

    base
    |> Map.drop(["_method", "_csrf_token", "id"])
  end

  defp admin_skills_path(_conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/skills"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
