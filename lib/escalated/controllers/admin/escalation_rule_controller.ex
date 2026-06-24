defmodule Escalated.Controllers.Admin.EscalationRuleController do
  @moduledoc """
  Admin CRUD over EscalationRule rows + manual `run` trigger.

  Mirrors the Laravel `EscalationRuleController`. Escalation rules are
  time-based (evaluated by `mix escalated.evaluate_escalations`), distinct
  from event-driven Workflows and the general Automation runner.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.EscalationRule
  alias Escalated.Services.EscalationService

  def index(conn, _params) do
    repo = Escalated.repo()

    rules =
      EscalationRule
      |> EscalationRule.active()
      |> repo.all()

    UIRenderer.render_page(conn, "Escalated/Admin/EscalationRules/Index", %{
      rules: Enum.map(rules, &EscalationRule.to_json/1)
    })
  end

  def show(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(EscalationRule, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Escalation rule not found"})

      rule ->
        UIRenderer.render_page(conn, "Escalated/Admin/EscalationRules/Show", %{
          rule: EscalationRule.to_json(rule)
        })
    end
  end

  def create(conn, %{"escalation_rule" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    repo = Escalated.repo()

    %EscalationRule{}
    |> EscalationRule.changeset(params)
    |> repo.insert()
    |> case do
      {:ok, _rule} ->
        conn |> put_flash(:info, "Escalation rule created.") |> redirect(to: admin_path(conn))

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "escalation_rule" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case repo.get(EscalationRule, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Escalation rule not found"})

      rule ->
        rule
        |> EscalationRule.changeset(params)
        |> repo.update()
        |> case do
          {:ok, _} ->
            conn |> put_flash(:info, "Escalation rule updated.") |> redirect(to: admin_path(conn))

          {:error, cs} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(EscalationRule, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Escalation rule not found"})

      rule ->
        repo.delete(rule)
        conn |> put_flash(:info, "Escalation rule deleted.") |> redirect(to: admin_path(conn))
    end
  end

  @doc "Manually trigger the escalation evaluator (admin smoke-test)."
  def run(conn, _params) do
    affected = EscalationService.evaluate_rules(Escalated.repo())
    Phoenix.Controller.json(conn, %{affected: affected})
  end

  defp admin_path(_conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/escalation-rules"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
