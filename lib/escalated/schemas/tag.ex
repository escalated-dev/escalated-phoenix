defmodule Escalated.Schemas.Tag do
  @moduledoc """
  Ecto schema for ticket tags.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}tags" do
    field :tenant_id, :string, default: ""
    field :name, :string
    field :color, :string, default: "#6B7280"

    many_to_many :tickets, Escalated.Schemas.Ticket,
      join_through: Escalated.Schemas.TicketTag,
      join_defaults: {Escalated.Schemas.TicketTag, :tenant_defaults, []}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> validate_required([:name])
    |> unique_constraint(:name)
    |> Escalated.Tenancy.Constraints.add_unique_constraints()
  end

  def ordered(query \\ __MODULE__) do
    from(t in query, order_by: [asc: t.name])
  end
end
