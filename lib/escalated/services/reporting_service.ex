defmodule Escalated.Services.ReportingService do
  @moduledoc """
  Advanced reporting service with percentile calculations, cohort analysis,
  and period comparison.
  """

  import Ecto.Query

  @doc "Calculate percentiles (p50, p75, p90, p95, p99) from a list of values"
  def percentiles(values) when is_list(values) and length(values) > 0 do
    sorted = Enum.sort(values)

    %{
      p50: percentile_value(sorted, 50),
      p75: percentile_value(sorted, 75),
      p90: percentile_value(sorted, 90),
      p95: percentile_value(sorted, 95),
      p99: percentile_value(sorted, 99)
    }
  end

  def percentiles(_), do: %{}

  @doc "Build a distribution with buckets and stats"
  def build_distribution(values, unit) when is_list(values) and length(values) > 0 do
    sorted = Enum.sort(values)
    max_val = List.last(sorted)
    bucket_size = max(ceil_int(max_val / 10), 1)

    buckets =
      0..ceil_int(max_val)
      |> Enum.take_every(bucket_size)
      |> Enum.map(fn start ->
        range_end = start + bucket_size
        count = Enum.count(sorted, fn v -> v >= start and v < range_end end)
        %{range: "#{start}-#{range_end}", count: count}
      end)
      |> Enum.filter(fn b -> b.count > 0 end)

    avg = Float.round(Enum.sum(sorted) / length(sorted), 2)

    %{
      buckets: buckets,
      stats: %{
        min: List.first(sorted),
        max: List.last(sorted),
        avg: avg,
        median: percentile_value(sorted, 50),
        count: length(sorted),
        unit: unit
      },
      percentiles: percentiles(sorted)
    }
  end

  def build_distribution(_, _), do: %{buckets: [], stats: %{}}

  @doc "Calculate composite performance score"
  def composite_score(resolution_rate, avg_frt, avg_resolution, avg_csat) do
    {score, weights} = {0.0, 0.0}

    {score, weights} =
      if resolution_rate do
        {score + resolution_rate / 100 * 30, weights + 30}
      else
        {score, weights}
      end

    {score, weights} =
      if avg_frt && avg_frt > 0 do
        {score + max(1.0 - avg_frt / 24.0, 0) * 25, weights + 25}
      else
        {score, weights}
      end

    {score, weights} =
      if avg_resolution && avg_resolution > 0 do
        {score + max(1.0 - avg_resolution / 72.0, 0) * 25, weights + 25}
      else
        {score, weights}
      end

    {score, weights} =
      if avg_csat do
        {score + avg_csat / 5.0 * 20, weights + 20}
      else
        {score, weights}
      end

    if weights > 0, do: Float.round(score / weights * 100, 1), else: 0.0
  end

  @doc "Generate date series between from and to (max 90 days)"
  def date_series(from, to) do
    days = min(max(Date.diff(to, from) + 1, 1), 90)
    Enum.map(0..(days - 1), fn i -> Date.add(from, i) end)
  end

  @doc "Calculate percentage changes between current and previous period stats"
  def calculate_changes(current, previous) do
    keys = [:total_created, :total_resolved, :resolution_rate]

    Enum.into(keys, %{}, fn key ->
      cur = Map.get(current, key, 0) |> to_float()
      prev = Map.get(previous, key, 0) |> to_float()

      change =
        if prev == 0.0 do
          if cur > 0, do: 100.0, else: 0.0
        else
          Float.round((cur - prev) / prev * 100, 1)
        end

      {key, change}
    end)
  end

  # Private helpers

  defp percentile_value(sorted, p) do
    if length(sorted) == 1 do
      Float.round(hd(sorted) / 1, 2)
    else
      k = p / 100 * (length(sorted) - 1)
      f = floor(k) |> trunc()
      c = ceil(k) |> trunc()

      if f == c do
        Float.round(Enum.at(sorted, f) / 1, 2)
      else
        val = Enum.at(sorted, f) + (k - f) * (Enum.at(sorted, c) - Enum.at(sorted, f))
        Float.round(val, 2)
      end
    end
  end

  defp ceil_int(val) when is_float(val), do: val |> Float.ceil() |> trunc()
  defp ceil_int(val) when is_integer(val), do: val

  defp floor(val) when is_float(val), do: Float.floor(val)
  defp floor(val) when is_integer(val), do: val * 1.0

  defp ceil(val) when is_float(val), do: Float.ceil(val)
  defp ceil(val) when is_integer(val), do: val * 1.0

  defp to_float(val) when is_float(val), do: val
  defp to_float(val) when is_integer(val), do: val / 1
  defp to_float(nil), do: 0.0
  defp to_float(_), do: 0.0
end
