defmodule Escalated.Schemas.Reply do
  @moduledoc """
  Ecto schema for ticket replies and internal notes.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}replies" do
    field :body, :string
    field :is_internal, :boolean, default: false
    field :is_system, :boolean, default: false
    field :is_pinned, :boolean, default: false
    field :author_id, :integer

    belongs_to :ticket, Escalated.Schemas.Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:body, :is_internal, :is_system, :is_pinned, :author_id, :ticket_id])
    |> validate_required([:body, :ticket_id])
  end

  def chronological(query \\ __MODULE__) do
    from(r in query, order_by: [asc: r.inserted_at])
  end

  def reverse_chronological(query \\ __MODULE__) do
    from(r in query, order_by: [desc: r.inserted_at])
  end

  def internal_notes(query \\ __MODULE__) do
    from(r in query, where: r.is_internal == true)
  end

  def pinned(query \\ __MODULE__) do
    from(r in query, where: r.is_pinned == true and r.is_internal == true)
  end
end
