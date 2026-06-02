defmodule Escalated.Schemas.TicketSubject do
  @moduledoc """
  Join row linking a ticket to one host-app subject (`subject_type` + `subject_id`).
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}ticket_subjects" do
    field :subject_type, :string
    field :subject_id, :string
    field :role, :string
    field :position, :integer, default: 0

    belongs_to :ticket, Escalated.Schemas.Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:ticket_id, :subject_type, :subject_id, :role, :position])
    |> validate_required([:ticket_id, :subject_type, :subject_id])
    |> unique_constraint([:ticket_id, :subject_type, :subject_id],
      name: :escalated_ticket_subject_unique
    )
  end

  def ordered(query \\ __MODULE__) do
    from(s in query, order_by: [asc: s.position, asc: s.id])
  end

  def for_ticket(query \\ __MODULE__, ticket_id) do
    from(s in query, where: s.ticket_id == ^ticket_id)
  end
end
