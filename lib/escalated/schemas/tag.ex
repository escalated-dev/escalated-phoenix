defmodule Escalated.Schemas.Tag do
  @moduledoc """
  Ecto schema for ticket tags.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}tags" do
    field :name, :string
    field :color, :string, default: "#6B7280"

    many_to_many :tickets, Escalated.Schemas.Ticket,
      join_through: "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}ticket_tags"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :color])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end

  def ordered(query \\ __MODULE__) do
    from(t in query, order_by: [asc: t.name])
  end
end
