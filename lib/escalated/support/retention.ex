defmodule Escalated.Support.Retention do
  @moduledoc """
  Retention-policy day mapping shared by the `escalated.purge_expired`
  task and the admin data-retention settings. Mirrors the Laravel
  retention day map.
  """

  @days_map %{
    "never" => nil,
    "90_days" => 90,
    "180_days" => 180,
    "365_days" => 365,
    "1_year" => 365,
    "2_years" => 730,
    "3_years" => 1095,
    "5_years" => 1825
  }

  def days_map, do: @days_map

  @doc "Days for a retention setting value; nil for 'never' or an unknown value."
  def days_for(setting), do: Map.get(@days_map, setting)

  @doc "UTC cutoff datetime for a setting, or nil when retention is disabled."
  def cutoff_for(setting) do
    case days_for(setting) do
      nil ->
        nil

      days ->
        DateTime.utc_now() |> DateTime.add(-days * 86_400, :second) |> DateTime.truncate(:second)
    end
  end
end
