defmodule Escalated.Controllers.Agent.MacroController do
  @moduledoc """
  Agent endpoints for listing applicable macros and applying a macro
  to a specific ticket.

  See escalated-developer-context/domain-model/workflows-automations-macros.md.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Schemas.{Macro, Ticket}
  alias Escalated.Services.MacroService

  @doc """
  List macros visible to the current agent: shared + their own.
  """
  def index(conn, _params) do
    repo = Escalated.repo()
    agent_id = current_agent_id(conn) || 0
    macros = MacroService.list_for_agent(repo, agent_id)

    Phoenix.Controller.json(conn, Enum.map(macros, &Macro.to_json/1))
  end

  @doc """
  Apply a macro to a specific ticket.
  """
  def apply(conn, %{"ticket_id" => ticket_id, "macro_id" => macro_id}) do
    repo = Escalated.repo()

    with %Macro{} = macro <- repo.get(Macro, macro_id),
         %Ticket{} = ticket <- repo.get(Ticket, ticket_id) do
      agent_id = current_agent_id(conn) || 0
      updated = MacroService.apply(repo, macro, ticket, agent_id)

      Phoenix.Controller.json(conn, %{
        ok: true,
        ticket: %{
          id: updated.id,
          status: updated.status,
          priority: updated.priority,
          assigned_to: updated.assigned_to
        }
      })
    else
      nil ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Macro or ticket not found"})
    end
  end

  defp current_agent_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end
end
