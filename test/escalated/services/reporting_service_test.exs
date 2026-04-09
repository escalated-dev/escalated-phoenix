defmodule Escalated.Services.ReportingServiceTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.ReportingService

  describe "percentiles/1" do
    test "calculates p50 through p99" do
      values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
      result = ReportingService.percentiles(values)
      assert Map.has_key?(result, :p50)
      assert Map.has_key?(result, :p75)
      assert Map.has_key?(result, :p90)
      assert Map.has_key?(result, :p95)
      assert Map.has_key?(result, :p99)
      assert result.p50 == 5.5
    end

    test "returns empty map for empty list" do
      assert ReportingService.percentiles([]) == %{}
    end

    test "handles single value" do
      result = ReportingService.percentiles([42.0])
      assert result.p50 == 42.0
    end
  end

  describe "build_distribution/2" do
    test "creates distribution with buckets" do
      values = [1.0, 2.0, 3.0, 4.0, 5.0]
      result = ReportingService.build_distribution(values, "hours")
      assert length(result.buckets) > 0
      assert result.stats.count == 5
      assert result.stats.unit == "hours"
    end

    test "returns empty for empty values" do
      result = ReportingService.build_distribution([], "hours")
      assert result.buckets == []
    end
  end

  describe "composite_score/4" do
    test "calculates positive score" do
      score = ReportingService.composite_score(80.0, 2.0, 24.0, 4.5)
      assert is_float(score)
      assert score > 0
    end

    test "handles nil values" do
      score = ReportingService.composite_score(80.0, nil, nil, nil)
      assert is_float(score)
      assert score > 0
    end
  end

  describe "date_series/2" do
    test "generates correct number of dates" do
      from = ~D[2024-01-01]
      to = ~D[2024-01-10]
      dates = ReportingService.date_series(from, to)
      assert length(dates) == 10
    end

    test "caps at 90 days" do
      from = ~D[2024-01-01]
      to = ~D[2024-12-31]
      dates = ReportingService.date_series(from, to)
      assert length(dates) == 90
    end
  end

  describe "calculate_changes/2" do
    test "calculates percentage changes" do
      current = %{total_created: 100, total_resolved: 80, resolution_rate: 80.0}
      previous = %{total_created: 50, total_resolved: 40, resolution_rate: 80.0}
      changes = ReportingService.calculate_changes(current, previous)
      assert changes.total_created == 100.0
    end
  end
end
