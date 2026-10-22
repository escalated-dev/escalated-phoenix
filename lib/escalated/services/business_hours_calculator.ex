defmodule Escalated.Services.BusinessHoursCalculator do
  @moduledoc """
  Business-time arithmetic over a `Escalated.Schemas.BusinessSchedule`
  (escalated-laravel's `BusinessHoursCalculator`).

  Opening hours are wall-clock times in the schedule's time zone, but time is
  counted in real elapsed seconds, so a window on a daylight-saving change day
  is an hour shorter or longer than its wall-clock span. A wall time skipped by
  the change resolves to the moment the clocks go forward.

  A day's hours are `%{"start" => "09:00", "end" => "17:00"}`. A missing day,
  empty or unparseable times, equal start and end, or `"enabled" => false`
  close the day. `"24:00"` ends at the next midnight, and an end before the
  start is an overnight window that closes the next day. A window belongs to
  the local date it opens on: a holiday on that date closes it, overnight part
  included. Recurring holidays match on month and day in any year.

  A schedule with no usable window falls back to calendar time, so a policy is
  never left without a deadline. Results are in UTC. An unknown zone is UTC.
  """

  alias Escalated.Schemas.BusinessSchedule

  @tzdb Tz.TimeZoneDatabase
  @days ~w(monday tuesday wednesday thursday friday saturday sunday)
  # A schedule closed by holidays for ten years is treated as having no hours.
  @max_scan_days 3660

  @doc "Whether `zone` is an IANA time zone this calculator can use."
  def valid_timezone?(zone) when is_binary(zone) and zone != "" do
    match?({:ok, _}, DateTime.shift_zone(~U[2026-01-01 00:00:00Z], zone, @tzdb))
  end

  def valid_timezone?(_), do: false

  @doc "The instant `hours` (may be fractional) of business time after `from`."
  def add_business_hours(%DateTime{} = from, hours, schedule),
    do: add_business_seconds(from, round(hours * 3600), schedule)

  @doc "The instant `minutes` of business time after `from`."
  def add_business_minutes(%DateTime{} = from, minutes, schedule),
    do: add_business_seconds(from, round(minutes * 60), schedule)

  @doc "The instant `seconds` of business time after `from`, in UTC."
  def add_business_seconds(%DateTime{} = from, seconds, %BusinessSchedule{} = schedule) do
    from = to_utc(from)
    ctx = %{context(schedule) | total: seconds}

    cond do
      seconds <= 0 -> from
      not open_day?(ctx) -> DateTime.add(from, seconds, :second)
      # Start a day early: an overnight window opened yesterday may still be open.
      true -> scan(Date.add(local_date(from, ctx.zone), -1), 0, from, seconds, from, ctx)
    end
  end

  @doc "Whether `at` falls inside one of the schedule's windows."
  def within_business_hours?(%BusinessSchedule{} = schedule, %DateTime{} = at) do
    at = to_utc(at)
    ctx = context(schedule)
    today = local_date(at, ctx.zone)

    Enum.any?([Date.add(today, -1), today], fn day ->
      case window(day, ctx) do
        {start, finish} ->
          DateTime.compare(at, start) != :lt and DateTime.compare(at, finish) == :lt

        nil ->
          false
      end
    end)
  end

  def within_business_hours?(_, _), do: false

  # Private

  defp scan(_day, i, _cursor, _remaining, from, %{total: total}) when i >= @max_scan_days,
    do: DateTime.add(from, total, :second)

  defp scan(day, i, cursor, remaining, from, ctx) do
    case window(day, ctx) do
      {start, finish} ->
        if DateTime.compare(finish, cursor) == :gt do
          start = if DateTime.compare(cursor, start) == :gt, do: cursor, else: start
          available = DateTime.diff(finish, start, :second)

          if remaining <= available do
            DateTime.add(start, remaining, :second)
          else
            scan(Date.add(day, 1), i + 1, finish, remaining - available, from, ctx)
          end
        else
          scan(Date.add(day, 1), i + 1, cursor, remaining, from, ctx)
        end

      nil ->
        scan(Date.add(day, 1), i + 1, cursor, remaining, from, ctx)
    end
  end

  defp context(%BusinessSchedule{} = schedule) do
    zone = if valid_timezone?(schedule.timezone), do: schedule.timezone, else: "Etc/UTC"

    bounds =
      Map.new(@days, fn day ->
        {day, day_bounds(Map.get(schedule.hours || %{}, day))}
      end)

    holidays =
      case schedule.holidays do
        list when is_list(list) -> list
        _ -> []
      end

    %{zone: zone, bounds: bounds, holidays: holidays, total: 0}
  end

  defp open_day?(ctx), do: Enum.any?(ctx.bounds, fn {_day, b} -> b != nil end)

  # The window that opens on local date `day`, or nil.
  defp window(day, ctx) do
    with {start_min, end_min} <-
           Map.fetch!(ctx.bounds, Enum.at(@days, Date.day_of_week(day) - 1)),
         false <- holiday?(day, ctx.holidays) do
      start = wall_clock(day, start_min, ctx.zone)
      end_day = if end_min <= start_min, do: Date.add(day, 1), else: day
      finish = wall_clock(end_day, end_min, ctx.zone)

      if DateTime.compare(finish, start) == :gt, do: {start, finish}, else: nil
    else
      _ -> nil
    end
  end

  defp holiday?(day, holidays) do
    Enum.any?(holidays, fn
      %{date: %Date{} = date} = h ->
        if recurring?(h),
          do: date.month == day.month and date.day == day.day,
          else: Date.compare(date, day) == :eq

      _ ->
        false
    end)
  end

  defp recurring?(%{is_recurring: true}), do: true
  defp recurring?(_), do: false

  defp day_bounds(%{} = day) do
    with true <- Map.get(day, "enabled", Map.get(day, :enabled, true)) != false,
         {:ok, start} <- clock_minutes(Map.get(day, "start", Map.get(day, :start))),
         true <- start < 24 * 60,
         {:ok, finish} <- clock_minutes(Map.get(day, "end", Map.get(day, :end))),
         true <- finish != start do
      {start, finish}
    else
      _ -> nil
    end
  end

  defp day_bounds(_), do: nil

  # "HH:MM", 00:00 to 24:00, as minutes after midnight.
  defp clock_minutes(value) when is_binary(value) do
    with [hh, mm] <- String.split(String.trim(value), ":"),
         {h, ""} <- Integer.parse(hh),
         {m, ""} <- Integer.parse(mm),
         true <- h >= 0 and m >= 0 and m <= 59 and (h < 24 or (h == 24 and m == 0)) do
      {:ok, h * 60 + m}
    else
      _ -> :error
    end
  end

  defp clock_minutes(_), do: :error

  # The instant the clock in `zone` reads `minutes` past midnight on `day`.
  defp wall_clock(day, minutes, zone) when minutes >= 24 * 60,
    do: wall_clock(Date.add(day, 1), minutes - 24 * 60, zone)

  defp wall_clock(day, minutes, zone) do
    time = Time.new!(div(minutes, 60), rem(minutes, 60), 0)

    case DateTime.new(day, time, zone, @tzdb) do
      {:ok, dt} -> to_utc(dt)
      {:ambiguous, first, _second} -> to_utc(first)
      {:gap, _before, just_after} -> to_utc(just_after)
    end
  end

  defp local_date(%DateTime{} = utc, zone),
    do: utc |> DateTime.shift_zone!(zone, @tzdb) |> DateTime.to_date()

  defp to_utc(%DateTime{time_zone: "Etc/UTC"} = dt), do: dt
  defp to_utc(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC", @tzdb)
end
