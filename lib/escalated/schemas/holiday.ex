defmodule Escalated.Schemas.Holiday do
  @moduledoc """
  Ecto schema for holidays within a business schedule.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}holidays" do
    field :name, :string
    field :date, :date
    field :is_recurring, :boolean, default: false

    belongs_to :business_schedule, Escalated.Schemas.BusinessSchedule

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(holiday, attrs) do
    holiday
    |> cast(attrs, [:name, :date, :is_recurring, :business_schedule_id])
    |> validate_required([:name, :date, :business_schedule_id])
  end
end
