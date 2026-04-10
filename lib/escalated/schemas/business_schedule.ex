defmodule Escalated.Schemas.BusinessSchedule do
  @moduledoc """
  Ecto schema for business hours schedules with timezone support.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @default_hours %{
    "monday" => %{"start" => "09:00", "end" => "17:00", "enabled" => true},
    "tuesday" => %{"start" => "09:00", "end" => "17:00", "enabled" => true},
    "wednesday" => %{"start" => "09:00", "end" => "17:00", "enabled" => true},
    "thursday" => %{"start" => "09:00", "end" => "17:00", "enabled" => true},
    "friday" => %{"start" => "09:00", "end" => "17:00", "enabled" => true},
    "saturday" => %{"start" => "09:00", "end" => "17:00", "enabled" => false},
    "sunday" => %{"start" => "09:00", "end" => "17:00", "enabled" => false}
  }

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}business_schedules" do
    field :name, :string
    field :timezone, :string, default: "UTC"
    field :hours, :map, default: @default_hours
    field :is_default, :boolean, default: false
    field :is_active, :boolean, default: true

    has_many :holidays, Escalated.Schemas.Holiday

    timestamps(type: :utc_datetime)
  end

  def default_hours, do: @default_hours

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:name, :timezone, :hours, :is_default, :is_active])
    |> validate_required([:name, :timezone])
  end

  @doc "Check if a given datetime falls within this schedule's business hours."
  def within_business_hours?(%__MODULE__{hours: hours, holidays: holidays}, %DateTime{} = dt) do
    day_name = dt |> Calendar.strftime("%A") |> String.downcase()
    day_config = Map.get(hours, day_name)

    cond do
      is_nil(day_config) -> false
      not Map.get(day_config, "enabled", false) -> false
      is_holiday?(holidays, dt) -> false
      true ->
        time_str = Calendar.strftime(dt, "%H:%M")
        time_str >= Map.get(day_config, "start", "00:00") and
          time_str <= Map.get(day_config, "end", "23:59")
    end
  end

  def within_business_hours?(_, _), do: false

  defp is_holiday?(%Ecto.Association.NotLoaded{}, _dt), do: false
  defp is_holiday?(holidays, dt) when is_list(holidays) do
    date = DateTime.to_date(dt)
    Enum.any?(holidays, fn h -> Date.compare(h.date, date) == :eq end)
  end
  defp is_holiday?(_, _), do: false
end
