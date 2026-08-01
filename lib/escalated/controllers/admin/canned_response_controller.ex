defmodule Escalated.Controllers.Admin.CannedResponseController do
  @moduledoc """
  Admin CRUD over the shared canned-response library.

  Mirrors the automation/macro admin controllers. The agent-facing list
  (shared + own) lives in `Escalated.Controllers.Agent.CannedResponseController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.CannedResponse
  alias Escalated.Services.CannedResponseService

  def index(conn, _params) do
    responses = CannedResponseService.list(Escalated.repo())

    UIRenderer.render_page(conn, "Escalated/Admin/CannedResponses/Index", %{
      responses: Enum.map(responses, &CannedResponse.to_json/1)
    })
  end

  def show(conn, %{"id" => id}) do
    case CannedResponseService.find_by_id(Escalated.repo(), id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Canned response not found"})

      response ->
        UIRenderer.render_page(conn, "Escalated/Admin/CannedResponses/Show", %{
          response: CannedResponse.to_json(response)
        })
    end
  end

  def create(conn, %{"canned_response" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    params = stamp_creator(conn, params)

    case CannedResponseService.create(Escalated.repo(), params) do
      {:ok, _response} ->
        conn
        |> put_flash(:info, "Canned response created.")
        |> redirect(to: admin_canned_responses_path(conn))

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "canned_response" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case CannedResponseService.find_by_id(repo, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Canned response not found"})

      response ->
        case CannedResponseService.update(repo, response, params) do
          {:ok, _} ->
            conn
            |> put_flash(:info, "Canned response updated.")
            |> redirect(to: admin_canned_responses_path(conn))

          {:error, cs} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case CannedResponseService.find_by_id(repo, id) do
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Canned response not found"})

      response ->
        CannedResponseService.delete(repo, response)

        conn
        |> put_flash(:info, "Canned response deleted.")
        |> redirect(to: admin_canned_responses_path(conn))
    end
  end

  defp stamp_creator(conn, params) when is_map(params) do
    case current_agent_id(conn) do
      nil -> params
      id -> Map.put(params, "created_by", id)
    end
  end

  defp current_agent_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp admin_canned_responses_path(_conn) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/canned-responses"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
