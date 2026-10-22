defmodule Escalated.Schemas.BusinessSchedule do
  @moduledoc """
  Ecto schema for business hours schedules with timezone support.

  `hours` (the `schedule` the admin pages read and post) maps each weekday to
  `%{"start" => "09:00", "end" => "17:00"}`; empty times close the day. Rows
  written before the admin pages may carry `"enabled" => false` instead.
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
    field :tenant_id, :string, default: ""
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
    |> validate_length(:name, max: 255)
    |> validate_change(:timezone, fn :timezone, zone ->
      if Escalated.Timezones.known?(zone) or
           Escalated.Services.BusinessHoursCalculator.valid_timezone?(zone),
         do: [],
         else: [timezone: "is not a valid time zone"]
    end)
  end

  @doc """
  Every schedule as `%{id, name}`, by name: the `schedules` prop of the SLA
  policy and department forms (escalated-laravel passes
  `BusinessSchedule::orderBy('name')->get(['id', 'name'])`).
  """
  def options do
    import Ecto.Query, only: [from: 2]

    from(s in __MODULE__, order_by: [asc: s.name, asc: s.id], select: %{id: s.id, name: s.name})
    |> Escalated.repo().all()
  end

  @doc """
  Refuses a `business_schedule_id` change that names no schedule. A nil
  (clearing it) and an unchanged value pass.
  """
  def validate_reference(%Ecto.Changeset{} = changeset) do
    validate_change(changeset, :business_schedule_id, fn :business_schedule_id, id ->
      if Escalated.repo().get(__MODULE__, id),
        do: [],
        else: [business_schedule_id: "The selected business schedule is invalid."]
    end)
  end

  @doc """
  Check if a given datetime falls within this schedule's business hours,
  holidays included (`Escalated.Services.BusinessHoursCalculator`).
  """
  def within_business_hours?(%__MODULE__{} = schedule, %DateTime{} = dt),
    do: Escalated.Services.BusinessHoursCalculator.within_business_hours?(schedule, dt)

  def within_business_hours?(_, _), do: false
end
