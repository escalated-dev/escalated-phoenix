defmodule Escalated.Rendering.ReportScreens do
  @moduledoc """
  The figures the admin report screens read, in the shape they read them
  (escalated-laravel's `ReportController` and `Support\\ReportScreens`).

  Every chart reads a list of `%{label, value}`; agent tables read
  `agent_id` and `agent_name` with their own columns. The figures are
  computed in Elixir over the tickets created in the period, which keeps them
  identical on SQLite, PostgreSQL and MySQL. Report periods are bounded
  (`days`, at most a year), so the working set is the period's tickets.

  This backend records one `sla_breached` flag per ticket. Which deadline was
  missed is derived from the due dates: first response is breached when it
  came after its due time (or has not come and the due time has passed), and
  resolution likewise.
  """
  import Ecto.Query

  alias Escalated.Rendering.UserDirectory
  alias Escalated.Schemas.{Department, SatisfactionRating, SlaPolicy, Ticket}
  alias Escalated.Services.ReportingService

  @first_response_target_hours 4
  @resolution_target_hours 24
  @max_days 365

  def first_response_target_hours, do: @first_response_target_hours
  def resolution_target_hours, do: @resolution_target_hours

  @doc "The period in days from `period` or `days` (default 30, 1..365)."
  def period_days(params) do
    value = params["period"] || params["days"]

    case Integer.parse(to_string(value || "")) do
      {n, ""} when n > 0 -> min(n, @max_days)
      _ -> 30
    end
  end

  @doc "Tickets created in the `days` before `until` (now by default)."
  def tickets(days, until \\ DateTime.utc_now()) do
    since = DateTime.add(until, -days * 86_400, :second)

    from(t in Ticket, where: t.inserted_at >= ^since and t.inserted_at <= ^until)
    |> Escalated.repo().all()
  end

  @doc "Ratings given in the `days` before `until`."
  def ratings(days, until \\ DateTime.utc_now()) do
    since = DateTime.add(until, -days * 86_400, :second)

    from(r in SatisfactionRating, where: r.created_at >= ^since and r.created_at <= ^until)
    |> Escalated.repo().all()
  end

  # ---------------------------------------------------------------------------
  # Screens
  # ---------------------------------------------------------------------------

  @doc "`Escalated/Admin/Reports`: the overview."
  def overview(days) do
    tickets = tickets(days)
    ratings = ratings(days)

    %{
      period_days: days,
      total_tickets: length(tickets),
      resolved_tickets: Enum.count(tickets, & &1.resolved_at),
      avg_first_response_hours: avg(Enum.map(tickets, &first_response_hours/1)),
      sla_breach_count: Enum.count(tickets, &breached?/1),
      by_status: Enum.frequencies_by(tickets, & &1.status),
      by_priority: Enum.frequencies_by(tickets, & &1.priority),
      csat: %{
        average: avg(Enum.map(ratings, & &1.rating)),
        total: length(ratings),
        breakdown: Enum.frequencies_by(ratings, & &1.rating)
      }
    }
  end

  @doc "`Escalated/Admin/Reports/Dashboard`."
  def dashboard(days) do
    tickets = tickets(days)

    %{
      period_days: days,
      volume: volume(tickets),
      by_status: counts_by(tickets, & &1.status),
      by_priority: counts_by(tickets, & &1.priority),
      avg_response_hours: avg(Enum.map(tickets, &first_response_hours/1)),
      avg_resolution_hours: avg(Enum.map(tickets, &resolution_hours/1)),
      sla_compliance: sla_compliance(tickets),
      csat_average: avg(Enum.map(ratings(days), & &1.rating)),
      agent_performance: agent_performance(tickets)
    }
  end

  @doc "`Escalated/Admin/Reports/AgentMetrics`."
  def agent_metrics(days),
    do: %{period_days: days, agents: agent_performance(tickets(days))}

  @doc "`Escalated/Admin/Reports/SlaReport`."
  def sla_report(days) do
    tickets = tickets(days)

    policies =
      from(p in SlaPolicy, where: p.is_active == true, order_by: [asc: p.name])
      |> Escalated.repo().all()

    by_policy =
      Enum.map(policies, fn policy ->
        mine = Enum.filter(tickets, &(&1.sla_policy_id == policy.id))
        breached = Enum.count(mine, &breached?/1)

        %{
          policy_name: policy.name,
          total: length(mine),
          met: length(mine) - breached,
          breached: breached
        }
      end)

    names = Map.new(policies, &{&1.id, &1.name})

    breaches =
      tickets
      |> Enum.filter(&breached?/1)
      |> Enum.sort_by(&DateTime.to_unix(&1.inserted_at), :desc)
      |> Enum.take(100)
      |> Enum.map(fn t ->
        {frt, res} = breach_types(t)

        %{
          id: t.id,
          reference: t.reference,
          subject: t.subject,
          assigned_to: t.assigned_to,
          sla_policy_id: t.sla_policy_id,
          sla_policy:
            t.sla_policy_id && %{id: t.sla_policy_id, name: Map.get(names, t.sla_policy_id)},
          sla_first_response_breached: frt,
          sla_resolution_breached: res,
          first_response_at: iso(t.first_response_at),
          resolved_at: iso(t.resolved_at),
          created_at: iso(t.inserted_at)
        }
      end)

    %{
      period_days: days,
      compliance_rate: sla_compliance(tickets),
      compliance_by_policy: by_policy,
      breaches: breaches
    }
  end

  @doc "`Escalated/Admin/Reports/CsatReport`."
  def csat_report(days) do
    tickets = tickets(days)
    ratings = ratings(days)
    assignees = assignees(Enum.map(ratings, & &1.ticket_id))
    names = UserDirectory.lookup(Map.values(assignees))

    by_agent =
      ratings
      |> Enum.filter(&Map.get(assignees, &1.ticket_id))
      |> Enum.group_by(&Map.get(assignees, &1.ticket_id))
      |> Enum.map(fn {agent_id, rows} ->
        %{
          agent_id: agent_id,
          agent_name: agent_name(names, agent_id),
          avg_rating: avg(Enum.map(rows, & &1.rating)),
          total_ratings: length(rows)
        }
      end)
      |> Enum.sort_by(& &1.agent_name)

    over_time =
      ratings
      |> Enum.group_by(&date(&1.created_at))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {day, rows} -> %{label: day, value: avg(Enum.map(rows, & &1.rating))} end)

    %{
      period_days: days,
      csat_average: avg(Enum.map(ratings, & &1.rating)),
      response_rate: percent(length(ratings), length(tickets), 0.0),
      total_ratings: length(ratings),
      by_agent: by_agent,
      over_time: over_time
    }
  end

  @doc "`Escalated/Admin/Reports/Comparison`: this period against the one before."
  def comparison(days) do
    now = DateTime.utc_now()
    # The previous period ends the second before the current one starts, so a
    # ticket on the boundary is counted once.
    previous_end = DateTime.add(now, -days * 86_400 - 1, :second)

    side = fn tickets, ratings ->
      %{
        total_tickets: length(tickets),
        resolved_tickets: Enum.count(tickets, & &1.resolved_at),
        avg_frt: avg(Enum.map(tickets, &first_response_hours/1)),
        avg_resolution: avg(Enum.map(tickets, &resolution_hours/1)),
        sla_compliance: sla_compliance(tickets),
        csat: avg(Enum.map(ratings, & &1.rating)),
        breach_count: Enum.count(tickets, &breached?/1),
        volume_trend: volume(tickets)
      }
    end

    %{
      period_days: days,
      current: side.(tickets(days, now), ratings(days, now)),
      previous: side.(tickets(days, previous_end), ratings(days, previous_end))
    }
  end

  @doc "`Escalated/Admin/Reports/ResponseTimes`."
  def response_times(days) do
    tickets = tickets(days)
    measured = Enum.reject(tickets, &is_nil(first_response_hours(&1)))
    hours = &first_response_hours/1

    Map.merge(time_summary(measured, hours, @first_response_target_hours), %{
      period_days: days,
      target_hours: @first_response_target_hours,
      by_agent: agent_times(measured, hours),
      by_department: average_by(measured, hours, &department_label/2),
      by_priority: average_by(measured, hours, fn t, _ -> t.priority end)
    })
    |> rename(avg: :avg_frt, median: :median_frt, p90: :p90_frt)
  end

  @doc "`Escalated/Admin/Reports/ResolutionTimes`."
  def resolution_times(days) do
    tickets = tickets(days)
    measured = Enum.reject(tickets, &is_nil(resolution_hours(&1)))
    hours = &resolution_hours/1

    Map.merge(time_summary(measured, hours, @resolution_target_hours), %{
      period_days: days,
      target_hours: @resolution_target_hours,
      by_agent: agent_times(measured, hours),
      by_department: average_by(measured, hours, &department_label/2),
      by_channel: average_by(measured, hours, fn t, _ -> t.channel end)
    })
    |> rename(avg: :avg_resolution, median: :median_resolution, p90: :p90_resolution)
  end

  @doc "`Escalated/Admin/Reports/AgentRanking`."
  def agent_ranking(days) do
    tickets = tickets(days)
    ratings = ratings(days)
    assignees = assignees(Enum.map(ratings, & &1.ticket_id))

    agents =
      tickets
      |> agent_performance()
      |> Enum.map(fn row ->
        csat =
          ratings
          |> Enum.filter(
            &(to_string(Map.get(assignees, &1.ticket_id)) == to_string(row.agent_id))
          )
          |> Enum.map(& &1.rating)
          |> avg()

        resolution_rate = percent(row.resolved_tickets, row.total_tickets, 0.0)

        %{
          agent_id: row.agent_id,
          agent_name: row.agent_name,
          volume: row.total_tickets,
          resolution_rate: resolution_rate,
          avg_frt: row.avg_response_hours || 0,
          avg_resolution: row.avg_resolution_hours || 0,
          csat: csat,
          composite_score:
            ReportingService.composite_score(
              resolution_rate,
              row.avg_response_hours,
              row.avg_resolution_hours,
              if(csat > 0, do: csat)
            )
        }
      end)
      |> Enum.sort_by(& &1.composite_score, :desc)

    %{period_days: days, agents: agents}
  end

  # ---------------------------------------------------------------------------
  # Figures
  # ---------------------------------------------------------------------------

  defp agent_performance(tickets) do
    assigned = Enum.reject(tickets, &is_nil(&1.assigned_to))
    names = UserDirectory.lookup(Enum.map(assigned, & &1.assigned_to))

    assigned
    |> Enum.group_by(&to_string(&1.assigned_to))
    |> Enum.map(fn {_key, [first | _] = rows} ->
      %{
        agent_id: first.assigned_to,
        agent_name: agent_name(names, first.assigned_to),
        total_tickets: length(rows),
        resolved_tickets: Enum.count(rows, & &1.resolved_at),
        avg_response_hours: avg_or_nil(Enum.map(rows, &first_response_hours/1)),
        avg_resolution_hours: avg_or_nil(Enum.map(rows, &resolution_hours/1))
      }
    end)
    |> Enum.sort_by(& &1.total_tickets, :desc)
  end

  defp agent_times(tickets, hours) do
    assigned = Enum.reject(tickets, &is_nil(&1.assigned_to))
    names = UserDirectory.lookup(Enum.map(assigned, & &1.assigned_to))

    assigned
    |> Enum.group_by(&to_string(&1.assigned_to))
    |> Enum.map(fn {_key, [first | _] = rows} ->
      values = Enum.map(rows, hours)

      %{
        agent_id: first.assigned_to,
        agent_name: agent_name(names, first.assigned_to),
        count: length(rows),
        avg: avg(values),
        median: percentile(values, 50),
        p90: percentile(values, 90)
      }
    end)
    |> Enum.sort_by(& &1.agent_name)
  end

  defp time_summary(tickets, hours, target) do
    values = Enum.map(tickets, hours)

    %{
      avg: avg(values),
      median: percentile(values, 50),
      p90: percentile(values, 90),
      pct_under_target: percent(Enum.count(values, &(&1 <= target)), length(values), 0.0),
      distribution: distribution(values),
      trend:
        tickets
        |> Enum.group_by(&date(&1.inserted_at))
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {day, rows} -> %{label: day, value: avg(Enum.map(rows, hours))} end)
    }
  end

  @buckets [{"< 1h", 1}, {"1-4h", 4}, {"4-8h", 8}, {"8-24h", 24}, {"1-3d", 72}, {"> 3d", nil}]

  defp distribution(values) do
    {rows, _} =
      Enum.map_reduce(@buckets, 0, fn {label, upper}, lower ->
        count =
          Enum.count(values, fn v -> v >= lower and (is_nil(upper) or v < upper) end)

        {%{label: label, value: count}, upper}
      end)

    rows
  end

  defp average_by(tickets, hours, label_fun) do
    departments = department_names(tickets)

    tickets
    |> Enum.group_by(&label(label_fun.(&1, departments)))
    |> Enum.map(fn {name, rows} -> %{label: name, value: avg(Enum.map(rows, hours))} end)
    |> Enum.sort_by(& &1.label)
  end

  defp department_label(ticket, departments),
    do: Map.get(departments, ticket.department_id, "Unassigned")

  defp department_names(tickets) do
    case tickets |> Enum.map(& &1.department_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] ->
        %{}

      ids ->
        from(d in Department, where: d.id in ^ids, select: {d.id, d.name})
        |> Escalated.repo().all()
        |> Map.new()
    end
  end

  defp volume(tickets) do
    tickets
    |> Enum.frequencies_by(&date(&1.inserted_at))
    |> Enum.sort()
    |> Enum.map(fn {day, count} -> %{label: day, value: count} end)
  end

  defp counts_by(tickets, fun) do
    tickets
    |> Enum.frequencies_by(fun)
    |> Enum.sort()
    |> Enum.map(fn {key, count} -> %{label: label(key), value: count} end)
  end

  # Tickets under an SLA policy that met it, as a percentage; 100 with none.
  defp sla_compliance(tickets) do
    under_policy = Enum.reject(tickets, &is_nil(&1.sla_policy_id))
    met = Enum.count(under_policy, &(not breached?(&1)))
    percent(met, length(under_policy), 100.0)
  end

  defp assignees([]), do: %{}

  defp assignees(ticket_ids) do
    from(t in Ticket, where: t.id in ^Enum.uniq(ticket_ids), select: {t.id, t.assigned_to})
    |> Escalated.repo().all()
    |> Map.new()
  end

  @doc false
  def breached?(ticket) do
    {frt, res} = breach_types(ticket)
    ticket.sla_breached == true or frt or res
  end

  @doc false
  def breach_types(ticket) do
    {late?(ticket.sla_first_response_due_at, ticket.first_response_at),
     late?(ticket.sla_resolution_due_at, ticket.resolved_at || ticket.closed_at)}
  end

  defp late?(nil, _met_at), do: false
  defp late?(due, nil), do: DateTime.compare(DateTime.utc_now(), due) == :gt
  defp late?(due, met_at), do: DateTime.compare(met_at, due) == :gt

  defp first_response_hours(%{first_response_at: nil}), do: nil
  defp first_response_hours(t), do: hours_between(t.inserted_at, t.first_response_at)

  defp resolution_hours(%{resolved_at: nil}), do: nil
  defp resolution_hours(t), do: hours_between(t.inserted_at, t.resolved_at)

  defp hours_between(from, to), do: max(DateTime.diff(to, from, :second), 0) / 3600

  defp avg_or_nil(values) do
    case Enum.reject(values, &is_nil/1) do
      [] -> nil
      present -> avg(present)
    end
  end

  defp avg(values) do
    case Enum.reject(values, &is_nil/1) do
      [] -> 0.0
      present -> Float.round(Enum.sum(present) / length(present) * 1.0, 1)
    end
  end

  defp percentile([], _), do: 0.0

  defp percentile(values, p) do
    sorted = Enum.sort(values)
    index = max(ceil(p / 100 * length(sorted)) - 1, 0)
    Float.round(Enum.at(sorted, index) * 1.0, 1)
  end

  defp percent(_part, 0, empty), do: empty
  defp percent(part, whole, _empty), do: Float.round(part / whole * 100, 1)

  defp agent_name(names, id), do: UserDirectory.name(names, id) || to_string(id)

  defp rename(map, pairs) do
    Enum.reduce(pairs, map, fn {from, to}, acc ->
      {value, acc} = Map.pop(acc, from)
      Map.put(acc, to, value)
    end)
  end

  defp label(nil), do: "unknown"
  defp label(""), do: "unknown"
  defp label(value), do: to_string(value)

  defp date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()
  defp date(%NaiveDateTime{} = dt), do: dt |> NaiveDateTime.to_date() |> Date.to_iso8601()

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
