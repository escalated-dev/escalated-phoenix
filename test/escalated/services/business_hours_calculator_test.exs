defmodule Escalated.Services.BusinessHoursCalculatorTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.{BusinessSchedule, Holiday}
  alias Escalated.Services.BusinessHoursCalculator, as: Calc

  defp weekdays(start, finish) do
    open = %{"start" => start, "end" => finish}

    %{
      "monday" => open,
      "tuesday" => open,
      "wednesday" => open,
      "thursday" => open,
      "friday" => open,
      "saturday" => %{"start" => "", "end" => ""},
      "sunday" => %{"start" => "", "end" => ""}
    }
  end

  defp schedule(hours, opts \\ []) do
    %BusinessSchedule{
      timezone: Keyword.get(opts, :timezone, "UTC"),
      hours: hours,
      holidays: Keyword.get(opts, :holidays, [])
    }
  end

  defp holiday(date, recurring \\ false),
    do: %Holiday{name: "h", date: date, is_recurring: recurring}

  defp utc(y, m, d, h, min) do
    {:ok, dt} = DateTime.new(Date.new!(y, m, d), Time.new!(h, min, 0), "Etc/UTC")
    dt
  end

  defp add(s, from, minutes), do: Calc.add_business_minutes(from, minutes, s)

  defp assert_at(got, want) do
    assert got.time_zone == "Etc/UTC"
    assert DateTime.compare(got, want) == :eq, "got #{got}, want #{want}"
  end

  test "counts inside one day" do
    s = schedule(weekdays("09:00", "17:00"))
    assert_at(add(s, utc(2026, 4, 7, 10, 0), 90), utc(2026, 4, 7, 11, 30))
    assert_at(add(s, utc(2026, 4, 7, 7, 0), 30), utc(2026, 4, 7, 9, 30))
    assert_at(add(s, utc(2026, 4, 7, 16, 0), 60), utc(2026, 4, 7, 17, 0))
  end

  test "after hours rolls to the next opening" do
    s = schedule(weekdays("09:00", "17:00"))
    assert_at(add(s, utc(2026, 4, 7, 20, 0), 60), utc(2026, 4, 8, 10, 0))
    assert_at(add(s, utc(2026, 4, 7, 16, 0), 120), utc(2026, 4, 8, 10, 0))
    assert_at(add(s, utc(2026, 4, 7, 9, 0), 16 * 60), utc(2026, 4, 8, 17, 0))
  end

  test "skips the weekend" do
    s = schedule(weekdays("09:00", "17:00"))
    # Friday 2026-04-10 16:00 + 2h: one hour on Friday, one on Monday.
    assert_at(add(s, utc(2026, 4, 10, 16, 0), 120), utc(2026, 4, 13, 10, 0))
    assert_at(add(s, utc(2026, 4, 11, 12, 0), 60), utc(2026, 4, 13, 10, 0))
  end

  test "skips holidays, recurring ones in any year" do
    s = schedule(weekdays("09:00", "17:00"), holidays: [holiday(~D[2026-04-13])])
    assert_at(add(s, utc(2026, 4, 10, 16, 0), 120), utc(2026, 4, 14, 10, 0))

    # 2026-12-25 is a Friday.
    recurring = schedule(weekdays("09:00", "17:00"), holidays: [holiday(~D[2019-12-25], true)])
    assert_at(add(recurring, utc(2026, 12, 24, 16, 0), 120), utc(2026, 12, 28, 10, 0))

    one_off = schedule(weekdays("09:00", "17:00"), holidays: [holiday(~D[2025-12-25])])
    assert_at(add(one_off, utc(2026, 12, 24, 16, 0), 120), utc(2026, 12, 25, 10, 0))
  end

  test "an overnight window runs into the next day and belongs to the day it opens" do
    hours = %{"friday" => %{"start" => "22:00", "end" => "06:00"}}
    s = schedule(hours)
    assert_at(add(s, utc(2026, 4, 10, 23, 0), 120), utc(2026, 4, 11, 1, 0))
    # Saturday 03:00 is inside the window Friday opened.
    assert_at(add(s, utc(2026, 4, 11, 3, 0), 60), utc(2026, 4, 11, 4, 0))
    assert_at(add(s, utc(2026, 4, 11, 5, 0), 120), utc(2026, 4, 17, 23, 0))

    closed = schedule(hours, holidays: [holiday(~D[2026-04-10])])
    assert_at(add(closed, utc(2026, 4, 11, 3, 0), 60), utc(2026, 4, 17, 23, 0))
  end

  test "an end of 24:00 is the next midnight" do
    s = schedule(%{"monday" => %{"start" => "20:00", "end" => "24:00"}})
    assert_at(add(s, utc(2026, 4, 6, 23, 0), 120), utc(2026, 4, 13, 21, 0))
    assert Calc.within_business_hours?(s, utc(2026, 4, 6, 23, 59))
  end

  test "hours are wall-clock time in the schedule's zone, holidays its local dates" do
    s = schedule(weekdays("09:00", "17:00"), timezone: "America/New_York")
    # 12:00 UTC is 08:00 EDT: opens 13:00 UTC.
    assert_at(add(s, utc(2026, 4, 6, 12, 0), 60), utc(2026, 4, 6, 14, 0))
    # Monday 23:00 UTC is 19:00 in New York: after hours.
    assert_at(add(s, utc(2026, 4, 6, 23, 0), 60), utc(2026, 4, 7, 14, 0))

    # Tuesday 02:00 UTC is still Monday evening in New York.
    with_holiday = %{s | holidays: [holiday(~D[2026-04-07])]}
    assert_at(add(with_holiday, utc(2026, 4, 7, 2, 0), 60), utc(2026, 4, 8, 14, 0))
  end

  test "daylight saving changes are counted in real time" do
    ny = schedule(weekdays("09:00", "17:00"), timezone: "America/New_York")
    # DST starts Sunday 2026-03-08: Monday opens 09:00 EDT = 13:00 UTC.
    assert_at(add(ny, utc(2026, 3, 6, 21, 0), 120), utc(2026, 3, 9, 14, 0))
    # DST ends Sunday 2026-11-01: Monday opens 09:00 EST = 14:00 UTC.
    assert_at(add(ny, utc(2026, 10, 30, 20, 0), 120), utc(2026, 11, 2, 15, 0))

    # 01:00-05:00 on 2026-03-08 lasts three hours.
    spring =
      schedule(%{"sunday" => %{"start" => "01:00", "end" => "05:00"}},
        timezone: "America/New_York"
      )

    assert_at(add(spring, utc(2026, 3, 8, 6, 0), 180), utc(2026, 3, 8, 9, 0))
    assert_at(add(spring, utc(2026, 3, 8, 6, 0), 240), utc(2026, 3, 15, 6, 0))

    # 02:30 does not exist that day: the window opens at 03:00 EDT = 07:00 UTC.
    gap =
      schedule(%{"sunday" => %{"start" => "02:30", "end" => "04:00"}},
        timezone: "America/New_York"
      )

    assert_at(add(gap, utc(2026, 3, 8, 5, 0), 30), utc(2026, 3, 8, 7, 30))

    # 00:00-04:00 on 2026-11-01 lasts five hours.
    fall =
      schedule(%{"sunday" => %{"start" => "00:00", "end" => "04:00"}},
        timezone: "America/New_York"
      )

    assert_at(add(fall, utc(2026, 11, 1, 4, 0), 300), utc(2026, 11, 1, 9, 0))
  end

  test "a schedule without a usable window falls back to calendar time" do
    from = utc(2026, 4, 7, 10, 0)

    for hours <- [
          %{},
          %{"tuesday" => %{"start" => "09:00", "end" => "09:00"}},
          %{"tuesday" => %{"start" => "09:00", "end" => "17:00", "enabled" => false}},
          %{"tuesday" => %{"start" => "nine", "end" => "17:00"}}
        ] do
      assert_at(add(schedule(hours), from, 90), DateTime.add(from, 90 * 60, :second))
    end

    open = schedule(weekdays("09:00", "17:00"))
    assert_at(add(open, utc(2026, 4, 11, 10, 0), 0), utc(2026, 4, 11, 10, 0))
  end

  test "an unknown zone is read as UTC" do
    s = schedule(weekdays("09:00", "17:00"), timezone: "Mars/Olympus_Mons")
    assert_at(add(s, utc(2026, 4, 7, 8, 0), 60), utc(2026, 4, 7, 10, 0))
  end

  test "add_business_hours takes fractional hours" do
    s = schedule(weekdays("09:00", "17:00"))
    assert_at(Calc.add_business_hours(utc(2026, 4, 7, 16, 0), 1.5, s), utc(2026, 4, 8, 9, 30))
  end

  test "within_business_hours? edges" do
    s = schedule(weekdays("09:00", "17:00"))
    assert Calc.within_business_hours?(s, utc(2026, 4, 7, 9, 0))
    assert Calc.within_business_hours?(s, utc(2026, 4, 7, 16, 59))
    refute Calc.within_business_hours?(s, utc(2026, 4, 7, 17, 0))
    refute Calc.within_business_hours?(s, utc(2026, 4, 11, 12, 0))

    overnight = schedule(%{"friday" => %{"start" => "22:00", "end" => "06:00"}})
    assert Calc.within_business_hours?(overnight, utc(2026, 4, 11, 3, 0))
    refute Calc.within_business_hours?(overnight, utc(2026, 4, 11, 7, 0))
  end

  test "the old enabled-flag hours still read" do
    s = schedule(BusinessSchedule.default_hours())
    assert Calc.within_business_hours?(s, utc(2026, 4, 6, 10, 0))
    refute Calc.within_business_hours?(s, utc(2026, 4, 4, 10, 0))
  end
end
