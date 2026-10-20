defmodule Escalated.Schemas.Reply do
  @moduledoc """
  Ecto schema for ticket replies and internal notes.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}replies" do
    field :tenant_id, :string, default: ""
    field :body, :string
    field :is_internal, :boolean, default: false
    field :is_system, :boolean, default: false
    field :is_pinned, :boolean, default: false
    field :author_id, @user_id_type

    belongs_to :ticket, Escalated.Schemas.Ticket
    has_many :attachments, Escalated.Schemas.Attachment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reply, attrs) do
    reject_flag_aliases!(attrs)

    reply
    |> cast(attrs, [:body, :is_internal, :is_system, :is_pinned, :author_id, :ticket_id])
    |> validate_required([:body, :ticket_id])
  end

  # `cast/3` silently drops keys it does not know, so a note built with another
  # port's name for the internal flag (Laravel's `is_internal_note`) used to
  # save as a public reply the requester could read. Refuse those keys loudly
  # instead of letting the flag fall back to its `false` default.
  @flag_aliases [
    :is_internal_note,
    "is_internal_note",
    :internal,
    "internal",
    :is_note,
    "is_note"
  ]

  defp reject_flag_aliases!(attrs) when is_map(attrs) do
    case Enum.find(@flag_aliases, &Map.has_key?(attrs, &1)) do
      nil ->
        :ok

      key ->
        raise ArgumentError,
              "Reply.changeset/2 does not accept #{inspect(key)}; " <>
                "use :is_internal to mark a reply as an internal note"
    end
  end

  defp reject_flag_aliases!(_attrs), do: :ok

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
