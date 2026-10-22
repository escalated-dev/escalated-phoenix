defmodule Escalated.Controllers.Agent.DashboardController do
  @moduledoc """
  The agent dashboard, with the props `Escalated/Agent/Dashboard` reads:
  `stats`, `recentTickets`, `needsAttention` and `myPerformance`, as
  escalated-laravel's `Agent\\DashboardController` sends them.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Rendering.{TicketPresenter, UIRenderer}
  alias Escalated.Schemas.Ticket
  import Ecto.Query

  @open ~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened)

  def index(conn, _params) do
    user = conn.assigns[:current_user]
    repo = Escalated.repo()
    open = from(t in Ticket, where: t.status in ^@open)
    count = &repo.aggregate(&1, :count)

    UIRenderer.render_page(conn, "Escalated/Agent/Dashboard", %{
      stats: %{
        open: count.(open),
        my_assigned: count.(from(t in open, where: t.assigned_to == ^user.id)),
        unassigned: count.(from(t in open, where: is_nil(t.assigned_to))),
        sla_breached: count.(from(t in open, where: t.sla_breached == true)),
        resolved_today: count.(from(t in Ticket, where: t.resolved_at >= ^start_of_day()))
      },
      recentTickets:
        from(t in Ticket, order_by: [desc: t.inserted_at, desc: t.id], limit: 10)
        |> repo.all()
        |> TicketPresenter.rows(),
      needsAttention: %{
        sla_breaching:
          from(t in open, where: t.sla_breached == true, limit: 5)
          |> repo.all()
          |> TicketPresenter.rows(),
        unassigned_urgent:
          from(t in open,
            where: is_nil(t.assigned_to) and t.priority in ["urgent", "critical"],
            limit: 5
          )
          |> repo.all()
          |> TicketPresenter.rows()
      },
      myPerformance: %{
        resolved_this_week:
          count.(
            from(t in Ticket,
              where: t.assigned_to == ^user.id and t.resolved_at >= ^start_of_week()
            )
          )
      }
    })
  end

  defp start_of_day do
    DateTime.utc_now() |> DateTime.to_date() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end

  defp start_of_week do
    today = Date.utc_today()
    today |> Date.add(1 - Date.day_of_week(today)) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end
end
