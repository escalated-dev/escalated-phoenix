defmodule Escalated.Controllers.AgentDetailReportTest do
  @moduledoc """
  `Escalated/Admin/Reports/AgentDetail`, the per-agent screen the agent
  ranking links to, with the props the shared page declares: the period's
  KPIs against the period of the same length before it, response percentiles,
  and the productivity, workload and CSAT charts as `%{label, value}` rows.
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{Reply, SatisfactionRating, Ticket}

  defp repo, do: Escalated.repo()

  @declared ~w(agent avg_frt avg_resolution csat_breakdown csat_score period_days prev_avg_frt
               prev_avg_resolution prev_csat_score prev_resolved_tickets prev_total_tickets
               productivity resolved_tickets response_percentiles total_tickets workload)

  setup do
    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})
    agent = host_user!(%{name: "Al Agent", email: "al@example.com", is_agent: true})
    %{admin: admin, agent: agent}
  end

  defp ticket!(attrs) do
    %Ticket{}
    |> Ticket.changeset(%{subject: "S", description: "d"})
    |> Ecto.Changeset.change(attrs)
    |> repo().insert!()
  end

  defp detail(ctx, query \\ ""),
    do:
      visit(:get, "/support/admin/reports/agent/#{ctx.agent.id}/detail" <> query, ctx.admin)
      |> page!("Escalated/Admin/Reports/AgentDetail")

  test "sends the declared props and the figures behind them", ctx do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    # 10:00 two days ago, so the reply and the resolution land on the same day
    # whatever time the suite runs.
    {:ok, created} = DateTime.new(Date.add(DateTime.to_date(now), -2), ~T[10:00:00], "Etc/UTC")

    answered =
      ticket!(%{
        assigned_to: ctx.agent.id,
        inserted_at: created,
        status: "resolved",
        first_response_at: DateTime.add(created, 2 * 3600),
        resolved_at: DateTime.add(created, 4 * 3600)
      })

    ticket!(%{
      assigned_to: ctx.agent.id,
      inserted_at: created,
      first_response_at: DateTime.add(created, 4 * 3600)
    })

    # The period before, so the comparison has something to show.
    ticket!(%{assigned_to: ctx.agent.id, inserted_at: DateTime.add(now, -40 * 86_400)})
    # Someone else's ticket is not this agent's.
    ticket!(%{inserted_at: created})

    repo().insert!(%SatisfactionRating{ticket_id: answered.id, rating: 4, created_at: now})

    for internal <- [false, true] do
      repo().insert!(%Reply{
        ticket_id: answered.id,
        author_id: ctx.agent.id,
        body: "On it",
        is_internal: internal,
        inserted_at: DateTime.add(created, 2 * 3600),
        updated_at: DateTime.add(created, 2 * 3600)
      })
    end

    props = detail(ctx, "?days=30")
    day = created |> DateTime.to_date() |> Date.to_iso8601()

    assert (Map.keys(props) -- ~w(errors flash ziggy)) |> Enum.sort() == @declared
    assert props["period_days"] == 30

    assert props["agent"] == %{
             "id" => ctx.agent.id,
             "name" => "Al Agent",
             "email" => "al@example.com"
           }

    assert props["total_tickets"] == 2
    assert props["resolved_tickets"] == 1
    assert props["avg_frt"] == 3.0
    assert props["avg_resolution"] == 4.0
    assert props["csat_score"] == 4.0
    assert props["response_percentiles"]["p50"] == 3.0
    assert props["response_percentiles"]["p99"] == 4.0
    assert props["response_percentiles"] |> Map.keys() |> Enum.sort() == ~w(p50 p75 p90 p95 p99)
    # One public reply and one resolution that day; the internal note is not counted.
    assert props["productivity"] == [%{"label" => day, "value" => 2, "values" => [1, 1]}]
    assert props["workload"] == [%{"label" => day, "value" => 2}]
    assert props["csat_breakdown"] == [%{"label" => "4 stars", "value" => 1}]
    assert props["prev_total_tickets"] == 1
    assert props["prev_resolved_tickets"] == 0
    assert props["prev_csat_score"] == nil
  end

  test "an agent with no tickets", ctx do
    props = detail(ctx)

    assert props["period_days"] == 30
    assert props["total_tickets"] == 0
    assert props["csat_score"] == nil

    assert props["response_percentiles"] == %{
             "p50" => 0.0,
             "p75" => 0.0,
             "p90" => 0.0,
             "p95" => 0.0,
             "p99" => 0.0
           }

    assert props["productivity"] == []
    assert props["workload"] == []
    assert props["csat_breakdown"] == []
    refute Map.has_key?(props, "agent_id")
    refute Map.has_key?(props, "metrics")
  end

  test "admins only", ctx do
    assert visit(:get, "/support/admin/reports/agent/#{ctx.agent.id}/detail", ctx.agent).status ==
             403
  end
end
