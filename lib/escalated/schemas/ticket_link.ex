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
    |> put_unique_constraints()
  end

  @unique_fields [:parent_ticket_id, :child_ticket_id, :link_type]

  # The name Ecto derives for a three-column index on this table is 71
  # characters. PostgreSQL truncates identifiers at 63 bytes, so the index on
  # disk is named something `unique_constraint/2` never derives -- and a
  # duplicate link raised Ecto.ConstraintError, a 500, instead of coming back as
  # a changeset error. SQLite keeps the full name and never noticed.
  #
  # New installs get the short explicit name from the migration. The other two
  # are what existing installs already have, and an unmatched name is inert, so
  # declaring all three is how one changeset works everywhere.
  @derived_index_name "#{@prefix}ticket_links_parent_ticket_id_child_ticket_id_link_type_index"

  @unique_index_names [
    "#{@prefix}ticket_links_unique",
    @derived_index_name,
    String.slice(@derived_index_name, 0, 63)
  ]

  defp put_unique_constraints(changeset) do
    Enum.reduce(@unique_index_names, changeset, fn name, acc ->
      unique_constraint(acc, @unique_fields, name: name)
    end)
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
