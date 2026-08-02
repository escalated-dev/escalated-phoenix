defmodule Escalated.Controllers.Admin.AgentSearchController do
  @moduledoc """
  Autocomplete endpoint backing the @mention composer: given a `q` query,
  return matching agent/admin users as `[%{id, name, email}]`.

  Mirrors the Laravel `Admin\\AgentSearchController` (single `__invoke`
  action). An empty or missing query returns an empty list rather than the
  whole user table.
  """
  use Phoenix.Controller, formats: [:json]

  alias Escalated.Services.MentionService

  @doc "GET /support/admin/agents/search?q=... — agent suggestions as JSON."
  def search(conn, params) do
    query = params |> Map.get("q", "") |> to_string()

    Phoenix.Controller.json(conn, MentionService.agent_suggestions(query))
  end
end
