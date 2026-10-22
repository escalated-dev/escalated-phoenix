defmodule Escalated.Services.SlaBusinessHoursTest do
  @moduledoc """
  SLA deadlines in business time: with business hours on, the schedule is the
  policy's, else the ticket department's, else the default one. With no
  schedule at all, the configured hours apply exactly as before.
  """
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{BusinessSchedule, Department, Holiday, SlaPolicy, Ticket}
  alias Escalated.Services.SlaService

  defp repo, do: Escalated.repo()

  # Friday 2026-04-10 16:00 UTC.
  @friday ~U[2026-04-10 16:00:00Z]
  @two_hours %{"low" => 2, "medium" => 2, "high" => 2, "urgent" => 2, "critical" => 2}

  setup do
    # targeted_slas anchors deadlines on inserted_at, which the tests fix.
    Application.put_env(:escalated, :targeted_slas, true)

    Application.put_env(:escalated, :sla, %{
      enabled: true,
      business_hours_only: true,
      # Legacy configured hours: weekdays 09:00-12:00 UTC.
      business_hours: %{start: 9, end_hour: 12, working_days: [1, 2, 3, 4, 5]}
    })

    on_exit(fn ->
      for key <- [:sla, :targeted_slas], do: Application.delete_env(:escalated, key)
    end)

    :ok
  end

  defp schedule!(name, hours, attrs \\ %{}) do
    %BusinessSchedule{}
    |> BusinessSchedule.changeset(Map.merge(%{name: name, timezone: "UTC", hours: hours}, attrs))
    |> repo().insert!()
  end

  defp weekdays(start, finish) do
    open = %{"start" => start, "end" => finish}
    Map.new(~w(monday tuesday wednesday thursday friday), &{&1, open})
  end

  defp policy!(attrs \\ %{}) do
    %SlaPolicy{}
    |> SlaPolicy.changeset(
      Map.merge(
        %{
          name: "P#{System.unique_integer([:positive])}",
          first_response_hours: @two_hours,
          resolution_hours: @two_hours
        },
        attrs
      )
    )
    |> repo().insert!()
  end

  defp ticket!(attrs \\ %{}) do
    %Ticket{inserted_at: @friday, updated_at: @friday}
    |> Ticket.changeset(Map.merge(%{subject: "S", description: "d"}, attrs))
    |> repo().insert!()
  end

  defp due(ticket, policy) do
    {:ok, updated} = SlaService.attach_policy(ticket, policy)
    updated = repo().get!(Ticket, updated.id)
    {updated.sla_first_response_due_at, updated.sla_resolution_due_at}
  end

  test "the policy's schedule comes first" do
    policy_schedule = schedule!("Policy", weekdays("09:00", "17:00"))
    dept_schedule = schedule!("Dept", weekdays("13:00", "14:00"))
    schedule!("Default", weekdays("15:00", "16:00"), %{is_default: true})

    dept =
      repo().insert!(
        Department.changeset(%Department{}, %{
          name: "Billing",
          business_schedule_id: dept_schedule.id
        })
      )

    policy = policy!(%{business_schedule_id: policy_schedule.id})

    # One hour Friday, one hour Monday from 09:00.
    assert due(ticket!(%{department_id: dept.id}), policy) ==
             {~U[2026-04-13 10:00:00Z], ~U[2026-04-13 10:00:00Z]}
  end

  test "then the ticket department's schedule" do
    dept_schedule = schedule!("Dept", weekdays("13:00", "14:00"))
    schedule!("Default", weekdays("15:00", "16:00"), %{is_default: true})

    dept =
      repo().insert!(
        Department.changeset(%Department{}, %{
          name: "Billing",
          business_schedule_id: dept_schedule.id
        })
      )

    # Friday's window is over; Monday and Tuesday 13:00-14:00.
    assert due(ticket!(%{department_id: dept.id}), policy!()) ==
             {~U[2026-04-14 14:00:00Z], ~U[2026-04-14 14:00:00Z]}
  end

  test "then the default schedule, holidays included" do
    default = schedule!("Default", weekdays("09:00", "17:00"), %{is_default: true})

    repo().insert!(
      Holiday.changeset(%Holiday{}, %{
        name: "Closed",
        date: ~D[2026-04-13],
        business_schedule_id: default.id
      })
    )

    schedule!("Other", weekdays("13:00", "14:00"))

    # One hour Friday; Monday is a holiday; one hour Tuesday.
    assert due(ticket!(), policy!()) == {~U[2026-04-14 10:00:00Z], ~U[2026-04-14 10:00:00Z]}
  end

  test "a policy schedule that no longer exists falls through" do
    schedule!("Default", weekdays("09:00", "17:00"), %{is_default: true})

    assert due(ticket!(), policy!(%{business_schedule_id: 999_999})) ==
             {~U[2026-04-13 10:00:00Z], ~U[2026-04-13 10:00:00Z]}
  end

  test "with no schedule configured, the configured hours apply as before" do
    schedule!("Not default", weekdays("13:00", "14:00"))

    # Legacy hours 09:00-12:00: Friday is over, Monday 09:00 + 2h.
    assert due(ticket!(), policy!()) == {~U[2026-04-13 11:00:00Z], ~U[2026-04-13 11:00:00Z]}
  end

  test "without business hours, deadlines stay in calendar time" do
    Application.put_env(:escalated, :sla, %{enabled: true, business_hours_only: false})
    schedule!("Default", weekdays("09:00", "17:00"), %{is_default: true})

    assert due(ticket!(), policy!()) == {~U[2026-04-10 18:00:00Z], ~U[2026-04-10 18:00:00Z]}
  end
end
