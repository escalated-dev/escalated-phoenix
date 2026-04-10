defmodule Escalated.Schemas.BusinessScheduleTest do
  use ExUnit.Case, async: true
  alias Escalated.Schemas.BusinessSchedule

  test "default hours have weekdays enabled" do
    hours = BusinessSchedule.default_hours()
    assert hours["monday"]["enabled"] == true
    assert hours["friday"]["enabled"] == true
    assert hours["saturday"]["enabled"] == false
    assert hours["sunday"]["enabled"] == false
  end

  test "within_business_hours? on a weekday during hours" do
    schedule = %BusinessSchedule{
      timezone: "UTC",
      hours: BusinessSchedule.default_hours(),
      holidays: []
    }

    # Monday at 10:00 UTC
    {:ok, dt} = DateTime.new(~D[2026-04-06], ~T[10:00:00], "Etc/UTC")
    assert BusinessSchedule.within_business_hours?(schedule, dt)
  end

  test "within_business_hours? on a weekend" do
    schedule = %BusinessSchedule{
      timezone: "UTC",
      hours: BusinessSchedule.default_hours(),
      holidays: []
    }

    # Saturday at 10:00 UTC
    {:ok, dt} = DateTime.new(~D[2026-04-04], ~T[10:00:00], "Etc/UTC")
    refute BusinessSchedule.within_business_hours?(schedule, dt)
  end

  test "within_business_hours? on a holiday" do
    schedule = %BusinessSchedule{
      timezone: "UTC",
      hours: BusinessSchedule.default_hours(),
      holidays: [%Escalated.Schemas.Holiday{name: "Test", date: ~D[2026-04-06]}]
    }

    {:ok, dt} = DateTime.new(~D[2026-04-06], ~T[10:00:00], "Etc/UTC")
    refute BusinessSchedule.within_business_hours?(schedule, dt)
  end
end
