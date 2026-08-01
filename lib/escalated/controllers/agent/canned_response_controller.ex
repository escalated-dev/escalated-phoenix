defmodule Escalated.Controllers.Agent.CannedResponseController do
  @moduledoc """
  Agent-facing list of canned responses: shared responses plus the ones the
  current agent created. Mirrors the Laravel `forAgent` scope surfaced on the
  ticket-show payload and the API resource endpoint.
  """
  use Phoenix.Controller, formats: [:json]

  alias Escalated.Schemas.CannedResponse
  alias Escalated.Services.CannedResponseService

  @doc "List canned responses visible to the current agent: shared + their own."
  def index(conn, _params) do
    repo = Escalated.repo()
    agent_id = current_agent_id(conn) || 0
    responses = CannedResponseService.list_for_agent(repo, agent_id)

    Phoenix.Controller.json(conn, Enum.map(responses, &CannedResponse.to_json/1))
  end

  defp current_agent_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end
end
