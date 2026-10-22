defmodule Escalated.Controllers.Admin.ReportController do
  @moduledoc """
  The admin report screens, with the props escalated-laravel's
  `ReportController` sends (see `Escalated.Rendering.ReportScreens`). Every
  screen takes the period as `days` (or `period`), default 30.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Rendering.{ReportScreens, UIRenderer}

  @screens %{
    overview: "Escalated/Admin/Reports",
    dashboard: "Escalated/Admin/Reports/Dashboard",
    agent_metrics: "Escalated/Admin/Reports/AgentMetrics",
    sla_report: "Escalated/Admin/Reports/SlaReport",
    csat_report: "Escalated/Admin/Reports/CsatReport",
    comparison: "Escalated/Admin/Reports/Comparison",
    response_times: "Escalated/Admin/Reports/ResponseTimes",
    resolution_times: "Escalated/Admin/Reports/ResolutionTimes",
    agent_ranking: "Escalated/Admin/Reports/AgentRanking",
    cohorts: "Escalated/Admin/Reports/Cohorts"
  }

  def index(conn, params), do: screen(conn, params, :overview)
  def dashboard(conn, params), do: screen(conn, params, :dashboard)
  def agents(conn, params), do: screen(conn, params, :agent_metrics)
  def sla(conn, params), do: screen(conn, params, :sla_report)
  def csat(conn, params), do: screen(conn, params, :csat_report)
  def comparison(conn, params), do: screen(conn, params, :comparison)
  def response_times(conn, params), do: screen(conn, params, :response_times)
  def resolution_times(conn, params), do: screen(conn, params, :resolution_times)
  def agent_ranking(conn, params), do: screen(conn, params, :agent_ranking)
  def cohorts(conn, params), do: screen(conn, params, :cohorts)

  def sla_trends(conn, params) do
    group_by = if params["group_by"] in ["week", "month"], do: params["group_by"], else: "day"
    props = ReportScreens.sla_trends(ReportScreens.period_days(params), group_by)
    UIRenderer.render_page(conn, "Escalated/Admin/Reports/SlaTrends", props)
  end

  defp screen(conn, params, name) do
    props = apply(ReportScreens, name, [ReportScreens.period_days(params)])
    UIRenderer.render_page(conn, Map.fetch!(@screens, name), props)
  end
end
