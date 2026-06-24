defmodule Escalated.Support.RetentionTest do
  use Escalated.DataCase, async: false

  alias Escalated.Services.SettingsService
  alias Escalated.Support.Retention

  describe "days_for/1" do
    test "maps known retention values" do
      assert Retention.days_for("90_days") == 90
      assert Retention.days_for("180_days") == 180
      assert Retention.days_for("1_year") == 365
      assert Retention.days_for("2_years") == 730
      assert Retention.days_for("5_years") == 1825
    end

    test "is nil for 'never' and unknown values" do
      assert Retention.days_for("never") == nil
      assert Retention.days_for("whenever") == nil
    end
  end

  describe "cutoff_for/1" do
    test "is nil when retention is disabled" do
      assert Retention.cutoff_for("never") == nil
    end

    test "is a datetime in the past for an active policy" do
      cutoff = Retention.cutoff_for("90_days")
      assert DateTime.compare(cutoff, DateTime.utc_now()) == :lt
    end
  end

  describe "settings store" do
    test "retention settings round-trip" do
      SettingsService.set("retention_audit_logs", "180_days", "retention")
      assert SettingsService.get_or_default("retention_audit_logs", "never") == "180_days"
    end
  end

  describe "modules load" do
    test "the controller and purge task are compiled" do
      assert Code.ensure_loaded?(Escalated.Controllers.Admin.DataRetentionController)
      assert Code.ensure_loaded?(Mix.Tasks.Escalated.PurgeExpired)
    end
  end
end
