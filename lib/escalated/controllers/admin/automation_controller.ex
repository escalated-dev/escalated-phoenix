defmodule Escalated.Controllers.Admin.AutomationController do
  @moduledoc """
  Admin CRUD over Automation rows + manual `run` trigger.

  Distinct from the Workflow controller (event-driven) and the Macro
  controller (agent manual). See escalated-developer-context/
  domain-model/workflows-automations-macros.md.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Schemas.Automation
  alias Escalated.Services.AutomationRunner
  alias Escalated.Rendering.UIRenderer

  def index(conn, _params) do
    repo = Escalated.repo()

    automations =
      Automation
      |> Automation.active()
      |> repo.all()

    UIRenderer.render_page(conn, "Escalated/Admin/Automations/Index", %{
      automations: Enum.map(automations, &Automation.to_json/1)
    })
  end

  def show(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Automation, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Automation not found"})

      automation ->
        UIRenderer.render_page(conn, "Escalated/Admin/Automations/Show", %{
          automation: Automation.to_json(automation)
        })
    end
  end

  def create(conn, %{"automation" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    repo = Escalated.repo()

    %Automation{}
    |> Automation.changeset(params)
    |> repo.insert()
    |> case do
      {:ok, _automation} ->
        conn |> put_flash(:info, "Automation created.") |> redirect(to: admin_automations_path(conn))

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "automation" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case repo.get(Automation, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Automation not found"})

      automation ->
        automation
        |> Automation.changeset(params)
        |> repo.update()
        |> case do
          {:ok, _} ->
            conn |> put_flash(:info, "Automation updated.") |> redirect(to: admin_automations_path(conn))

          {:error, cs} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Automation, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Automation not found"})

      automation ->
        repo.delete(automation)
        conn |> put_flash(:info, "Automation deleted.") |> redirect(to: admin_automations_path(conn))
    end
  end

  @doc """
  Manually trigger the runner. Useful for admin smoke-tests
  without waiting for the next scheduled tick.
  """
  def run(conn, _params) do
    repo = Escalated.repo()
    affected = AutomationRunner.run(repo)
    Phoenix.Controller.json(conn, %{affected: affected})
  end

  defp admin_automations_path(_conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/automations"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
