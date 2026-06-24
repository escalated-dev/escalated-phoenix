defmodule Escalated.Schemas.TicketLink do
  @moduledoc """
  A typed link between two tickets. Mirrors the Laravel `TicketLink`
  model. `link_type` is one of `problem_incident`, `parent_child`,
  `related`. Unique per (parent, child, link_type).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @link_types ~w(problem_incident parent_child related)
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}ticket_links" do
    field :parent_ticket_id, :id
    field :child_ticket_id, :id
    field :link_type, :string

    timestamps(type: :utc_datetime)
  end

  def link_types, do: @link_types

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:parent_ticket_id, :child_ticket_id, :link_type])
    |> validate_required([:parent_ticket_id, :child_ticket_id, :link_type])
    |> validate_inclusion(:link_type, @link_types)
    |> unique_constraint([:parent_ticket_id, :child_ticket_id, :link_type])
  end

  @doc "Serialize a link row for the frontend."
  def to_json(%__MODULE__{} = link) do
    %{
      id: link.id,
      parent_ticket_id: link.parent_ticket_id,
      child_ticket_id: link.child_ticket_id,
      link_type: link.link_type
    }
  end
end
