defmodule Escalated.Controllers.ReportPagesTest do
  @moduledoc """
  The admin report screens against the props the shared pages read
  (escalated-laravel's `ReportController` and `Support\\ReportScreens`):
  overview, dashboard, agents, SLA, CSAT, comparison, response times,
  resolution times and agent ranking.
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{Department, SatisfactionRating, SlaPolicy, Ticket}

  defp repo, do: Escalated.repo()

  @hours %{"low" => 24, "medium" => 8, "high" => 4, "urgent" => 2, "critical" => 1}

  setup do
    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})
    agent = host_user!(%{name: "Al Agent", is_agent: true})
    dept = repo().insert!(Department.changeset(%Department{}, %{name: "Billing"}))

    policy =
      repo().insert!(
        SlaPolicy.changeset(%SlaPolicy{}, %{
          name: "Standard",
          first_response_hours: @hours,
          resolution_hours: @hours
        })
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    created = DateTime.add(now, -2 * 86_400)

    ticket = fn attrs ->
      # Timestamps and SLA fields are set by the services, not cast; they are
      # written directly so the figures are known.
      %Ticket{}
      |> Ticket.changeset(%{subject: "S", description: "d"})
      |> Ecto.Changeset.change(Map.put(attrs, :inserted_at, created))
      |> repo().insert!()
    end

    # Answered in 2h, resolved in 10h, within its SLA.
    met =
      ticket.(%{
        assigned_to: agent.id,
        department_id: dept.id,
        sla_policy_id: policy.id,
        priority: "high",
        status: "resolved",
        first_response_at: DateTime.add(created, 2 * 3600),
        resolved_at: DateTime.add(created, 10 * 3600),
        sla_first_response_due_at: DateTime.add(created, 4 * 3600),
        sla_resolution_due_at: DateTime.add(created, 24 * 3600)
      })

    # First response came late.
    ticket.(%{
      assigned_to: agent.id,
      sla_policy_id: policy.id,
      priority: "low",
      first_response_at: DateTime.add(created, 6 * 3600),
      sla_first_response_due_at: DateTime.add(created, 4 * 3600)
    })

    repo().insert!(%SatisfactionRating{ticket_id: met.id, rating: 4, created_at: now})

    %{admin: admin, agent: agent}
  end

  defp screen(ctx, path, component),
    do: visit(:get, "/support/admin/reports" <> path, ctx.admin) |> page!(component)

  defp assert_series(list, label) do
    assert is_list(list), "#{label} is not a list"
    Enum.each(list, &assert_keys(&1, ~w(label value), label))
  end

  test "Reports overview", ctx do
    props = screen(ctx, "", "Escalated/Admin/Reports")

    assert_keys(
      props,
      ~w(period_days total_tickets resolved_tickets avg_first_response_hours sla_breach_count by_status by_priority csat)
    )

    assert props["total_tickets"] == 2
    assert props["sla_breach_count"] == 1
    assert_keys(props["csat"], ~w(average total breakdown), "csat")
    assert props["avg_first_response_hours"] == 4.0
  end

  test "Dashboard", ctx do
    props = screen(ctx, "/dashboard?days=7", "Escalated/Admin/Reports/Dashboard")

    assert_keys(
      props,
      ~w(period_days volume by_status by_priority avg_response_hours avg_resolution_hours sla_compliance csat_average agent_performance)
    )

    assert props["period_days"] == 7
    assert_series(props["volume"], "volume")
    assert_series(props["by_status"], "by_status")
    assert props["sla_compliance"] == 50.0
    assert props["csat_average"] == 4.0
    [agent] = props["agent_performance"]

    assert_keys(
      agent,
      ~w(agent_id agent_name total_tickets resolved_tickets avg_response_hours avg_resolution_hours),
      "agent"
    )

    assert agent["agent_name"] == "Al Agent"
    assert agent["total_tickets"] == 2
  end

  test "AgentMetrics", ctx do
    props = screen(ctx, "/agents", "Escalated/Admin/Reports/AgentMetrics")
    assert [%{"agent_name" => "Al Agent"}] = props["agents"]
  end

  test "SlaReport", ctx do
    props = screen(ctx, "/sla", "Escalated/Admin/Reports/SlaReport")

    assert_keys(props, ~w(period_days compliance_rate compliance_by_policy breaches))

    assert [%{"policy_name" => "Standard", "total" => 2, "met" => 1, "breached" => 1}] =
             props["compliance_by_policy"]

    [breach] = props["breaches"]

    assert_keys(
      breach,
      ~w(id reference subject sla_policy sla_first_response_breached sla_resolution_breached created_at),
      "breach"
    )

    assert breach["sla_first_response_breached"] == true
  end

  test "CsatReport", ctx do
    props = screen(ctx, "/csat", "Escalated/Admin/Reports/CsatReport")

    assert_keys(
      props,
      ~w(period_days csat_average response_rate total_ratings by_agent over_time)
    )

    assert props["total_ratings"] == 1
    assert props["response_rate"] == 50.0

    assert [%{"agent_name" => "Al Agent", "avg_rating" => 4.0, "total_ratings" => 1}] =
             props["by_agent"]

    assert_series(props["over_time"], "over_time")
  end

  test "Comparison", ctx do
    props = screen(ctx, "/comparison", "Escalated/Admin/Reports/Comparison")

    for side <- ["current", "previous"] do
      assert_keys(
        props[side],
        ~w(total_tickets resolved_tickets avg_frt avg_resolution sla_compliance csat breach_count volume_trend),
        side
      )
    end

    assert props["current"]["total_tickets"] == 2
    assert props["previous"]["total_tickets"] == 0
  end

  test "ResponseTimes and ResolutionTimes", ctx do
    props = screen(ctx, "/response-times", "Escalated/Admin/Reports/ResponseTimes")

    assert_keys(
      props,
      ~w(period_days avg_frt median_frt p90_frt pct_under_target target_hours distribution trend by_agent by_department by_priority)
    )

    assert props["avg_frt"] == 4.0
    assert props["pct_under_target"] == 50.0
    assert_series(props["distribution"], "distribution")
    [agent] = props["by_agent"]
    assert_keys(agent, ~w(agent_id agent_name count avg median p90), "agent")

    props = screen(ctx, "/resolution-times", "Escalated/Admin/Reports/ResolutionTimes")

    assert_keys(
      props,
      ~w(period_days avg_resolution median_resolution p90_resolution pct_under_target target_hours distribution trend by_agent by_department by_channel)
    )

    assert props["avg_resolution"] == 10.0
    assert [%{"label" => "Billing", "value" => 10.0}] = props["by_department"]
  end

  test "AgentRanking", ctx do
    props = screen(ctx, "/agent-ranking", "Escalated/Admin/Reports/AgentRanking")

    [agent] = props["agents"]

    assert_keys(
      agent,
      ~w(agent_id agent_name volume resolution_rate avg_frt avg_resolution csat composite_score),
      "agent"
    )

    assert agent["resolution_rate"] == 50.0
  end

  test "agents only see the reports of an admin's desk", ctx do
    assert visit(:get, "/support/admin/reports/dashboard", ctx.agent).status == 403
  end
end
