defmodule Escalated.Schemas.SlaPolicy do
  @moduledoc """
  Ecto schema for SLA (Service Level Agreement) policies.

  `first_response_hours` and `resolution_hours` are stored as maps:

      %{"low" => 24, "medium" => 8, "high" => 4, "urgent" => 2, "critical" => 1}
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}sla_policies" do
    field :name, :string
    field :description, :string
    field :is_active, :boolean, default: true
    field :is_default, :boolean, default: false
    field :first_response_hours, :map
    field :resolution_hours, :map

    has_many :tickets, Escalated.Schemas.Ticket
    has_many :departments, Escalated.Schemas.Department, foreign_key: :default_sla_policy_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(policy, attrs) do
    policy
    |> cast(attrs, [:name, :description, :is_active, :is_default, :first_response_hours, :resolution_hours])
    |> validate_required([:name, :first_response_hours, :resolution_hours])
    |> unique_constraint(:name)
  end

  def active(query \\ __MODULE__) do
    from(p in query, where: p.is_active == true)
  end

  def default_policy(query \\ __MODULE__) do
    from(p in query, where: p.is_default == true)
  end

  def ordered(query \\ __MODULE__) do
    from(p in query, order_by: [asc: p.name])
  end

  @doc """
  Returns the first response hours target for a given priority.
  """
  def first_response_hours_for(%__MODULE__{first_response_hours: hours}, priority)
      when is_map(hours) do
    case Map.get(hours, to_string(priority)) do
      nil -> nil
      val -> val / 1
    end
  end

  def first_response_hours_for(_, _), do: nil

  @doc """
  Returns the resolution hours target for a given priority.
  """
  def resolution_hours_for(%__MODULE__{resolution_hours: hours}, priority)
      when is_map(hours) do
    case Map.get(hours, to_string(priority)) do
      nil -> nil
      val -> val / 1
    end
  end

  def resolution_hours_for(_, _), do: nil
end
