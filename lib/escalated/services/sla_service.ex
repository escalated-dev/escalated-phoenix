defmodule Escalated.Services.SlaService do
  @moduledoc """
  Service for SLA policy management and breach detection.
  """

  alias Escalated.Schemas.{Ticket, SlaPolicy, TicketActivity}
  import Ecto.Query

  @doc """
  Attaches an SLA policy to a ticket and calculates due dates.
  """
  def attach_policy(ticket, policy \\ nil) do
    repo = Escalated.repo()

    policy = policy || find_policy_for(ticket)

    case policy do
      nil ->
        {:ok, ticket}

      policy ->
        first_response_hours = SlaPolicy.first_response_hours_for(policy, ticket.priority)
        resolution_hours = SlaPolicy.resolution_hours_for(policy, ticket.priority)

        ticket
        |> Ticket.changeset(%{
          sla_policy_id: policy.id,
          sla_first_response_due_at: calculate_due_date(first_response_hours),
          sla_resolution_due_at: calculate_due_date(resolution_hours)
        })
        |> repo.update()
    end
  end

  @doc """
  Checks all open tickets for SLA breaches and marks them.
  Returns a list of newly breached tickets.
  """
  def check_breaches do
    config = Escalated.configuration()
    unless Escalated.Config.sla_enabled?(config), do: throw(:sla_disabled)

    repo = Escalated.repo()
    now = DateTime.utc_now()
    breached = []

    # First response breaches
    first_response_breached =
      repo.all(
        from(t in Ticket,
          where:
            t.status in ^~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened) and
              t.sla_breached == false and
              not is_nil(t.sla_first_response_due_at) and
              is_nil(t.first_response_at) and
              t.sla_first_response_due_at < ^now
        )
      )

    breached =
      breached ++
        Enum.map(first_response_breached, fn ticket ->
          mark_breached(ticket, :first_response)
          ticket
        end)

    # Resolution breaches
    resolution_breached =
      repo.all(
        from(t in Ticket,
          where:
            t.status in ^~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened) and
              t.sla_breached == false and
              not is_nil(t.sla_resolution_due_at) and
              is_nil(t.resolved_at) and
              t.sla_resolution_due_at < ^now
        )
      )

    breached ++
      Enum.map(resolution_breached, fn ticket ->
        mark_breached(ticket, :resolution)
        ticket
      end)
  catch
    :sla_disabled -> []
  end

  @doc """
  Returns SLA statistics across all tickets.
  """
  def stats do
    config = Escalated.configuration()
    unless Escalated.Config.sla_enabled?(config), do: throw(:sla_disabled)

    repo = Escalated.repo()

    total = repo.aggregate(from(t in Ticket, where: not is_nil(t.sla_policy_id)), :count)
    breached = repo.aggregate(from(t in Ticket, where: t.sla_breached == true), :count)

    on_time_responses =
      repo.aggregate(
        from(t in Ticket,
          where:
            not is_nil(t.first_response_at) and
              not is_nil(t.sla_first_response_due_at) and
              t.first_response_at <= t.sla_first_response_due_at
        ),
        :count
      )

    total_responded =
      repo.aggregate(
        from(t in Ticket,
          where: not is_nil(t.first_response_at) and not is_nil(t.sla_first_response_due_at)
        ),
        :count
      )

    on_time_resolutions =
      repo.aggregate(
        from(t in Ticket,
          where:
            not is_nil(t.resolved_at) and
              not is_nil(t.sla_resolution_due_at) and
              t.resolved_at <= t.sla_resolution_due_at
        ),
        :count
      )

    total_resolved =
      repo.aggregate(
        from(t in Ticket,
          where: not is_nil(t.resolved_at) and not is_nil(t.sla_resolution_due_at)
        ),
        :count
      )

    %{
      total_with_sla: total,
      total_breached: breached,
      breach_rate: if(total > 0, do: Float.round(breached / total * 100, 1), else: 0.0),
      first_response_on_time: on_time_responses,
      first_response_on_time_rate:
        if(total_responded > 0,
          do: Float.round(on_time_responses / total_responded * 100, 1),
          else: 0.0
        ),
      resolution_on_time: on_time_resolutions,
      resolution_on_time_rate:
        if(total_resolved > 0,
          do: Float.round(on_time_resolutions / total_resolved * 100, 1),
          else: 0.0
        )
    }
  catch
    :sla_disabled -> %{}
  end

  @doc """
  Calculates a due date from now, optionally respecting business hours.
  """
  def calculate_due_date(nil), do: nil

  def calculate_due_date(hours) do
    config = Escalated.configuration()

    if config.sla[:business_hours_only] do
      calculate_business_hours_due_date(hours, config.sla[:business_hours] || %{})
    else
      DateTime.add(DateTime.utc_now(), trunc(hours * 3600), :second)
    end
  end

  # Private

  defp find_policy_for(ticket) do
    repo = Escalated.repo()

    cond do
      ticket.department_id ->
        dept = repo.get(Escalated.Schemas.Department, ticket.department_id)

        if dept && dept.default_sla_policy_id do
          repo.get(SlaPolicy, dept.default_sla_policy_id)
        else
          repo.one(from(p in SlaPolicy, where: p.is_default == true, limit: 1))
        end

      true ->
        repo.one(from(p in SlaPolicy, where: p.is_default == true, limit: 1))
    end
  end

  defp mark_breached(ticket, breach_type) do
    repo = Escalated.repo()

    repo.transaction(fn ->
      ticket
      |> Ticket.changeset(%{sla_breached: true})
      |> repo.update!()

      %TicketActivity{}
      |> TicketActivity.changeset(%{
        ticket_id: ticket.id,
        action: "sla_breached",
        details: %{breach_type: to_string(breach_type)}
      })
      |> repo.insert!()
    end)
  end

  defp calculate_business_hours_due_date(hours, bh) do
    start_hour = Map.get(bh, :start, 9)
    end_hour = Map.get(bh, :end_hour, 17)
    working_days = Map.get(bh, :working_days, [1, 2, 3, 4, 5])

    now = DateTime.utc_now()
    remaining = hours * 1.0
    advance_through_business_hours(now, remaining, start_hour, end_hour, working_days)
  end

  defp advance_through_business_hours(current, remaining, start_h, end_h, working_days)
       when remaining <= 0 do
    current
  end

  defp advance_through_business_hours(current, remaining, start_h, end_h, working_days) do
    day_of_week = Date.day_of_week(DateTime.to_date(current))

    if day_of_week in working_days do
      day_start = %{current | hour: start_h, minute: 0, second: 0}
      day_end = %{current | hour: end_h, minute: 0, second: 0}

      effective_start = if DateTime.compare(current, day_start) == :lt, do: day_start, else: current

      if DateTime.compare(effective_start, day_end) == :lt do
        available_seconds = DateTime.diff(day_end, effective_start, :second)
        needed_seconds = trunc(remaining * 3600)

        if needed_seconds <= available_seconds do
          DateTime.add(effective_start, needed_seconds, :second)
        else
          remaining = remaining - available_seconds / 3600
          next_day = current |> DateTime.add(86_400, :second) |> Map.merge(%{hour: start_h, minute: 0, second: 0})
          advance_through_business_hours(next_day, remaining, start_h, end_h, working_days)
        end
      else
        next_day = current |> DateTime.add(86_400, :second) |> Map.merge(%{hour: start_h, minute: 0, second: 0})
        advance_through_business_hours(next_day, remaining, start_h, end_h, working_days)
      end
    else
      next_day = current |> DateTime.add(86_400, :second) |> Map.merge(%{hour: start_h, minute: 0, second: 0})
      advance_through_business_hours(next_day, remaining, start_h, end_h, working_days)
    end
  end
end
