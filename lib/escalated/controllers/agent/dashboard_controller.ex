defmodule Escalated.Controllers.Agent.DashboardController do
  @moduledoc """
  Agent dashboard controller showing ticket overview and metrics.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Schemas.Ticket
  alias Escalated.Rendering.UIRenderer
  import Ecto.Query

  def index(conn, _params) do
    user = conn.assigns[:current_user]
    repo = Escalated.repo()

    my_open =
      repo.aggregate(
        from(t in Ticket, where: t.assigned_to == ^user.id and t.status in ^~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened)),
        :count
      )

    unassigned = repo.aggregate(Ticket.unassigned() |> Ticket.by_open(), :count)
    total_open = repo.aggregate(Ticket.by_open(), :count)
    breached = repo.aggregate(from(t in Ticket, where: t.sla_breached == true and t.status in ^~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened)), :count)

    recent_tickets =
      repo.all(
        from(t in Ticket,
          where: t.assigned_to == ^user.id,
          order_by: [desc: t.inserted_at],
          limit: 10
        )
      )

    UIRenderer.render_page(conn, "Escalated/Agent/Dashboard", %{
      stats: %{
        my_open: my_open,
        unassigned: unassigned,
        total_open: total_open,
        sla_breached: breached
      },
      recent_tickets:
        Enum.map(recent_tickets, fn t ->
          %{
            id: t.id,
            reference: t.reference,
            subject: t.subject,
            status: t.status,
            priority: t.priority,
            created_at: t.inserted_at && DateTime.to_iso8601(t.inserted_at)
          }
        end)
    })
  end
end
