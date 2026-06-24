defmodule Escalated.Schemas.SideConversation do
  @moduledoc """
  A side conversation thread attached to a ticket — an internal-note
  thread or an external email side-channel. Mirrors the Laravel
  `SideConversation` model.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)
  @channels ~w(internal email)
  @statuses ~w(open closed)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}side_conversations" do
    field :ticket_id, :id
    field :subject, :string
    field :channel, :string, default: "internal"
    field :status, :string, default: "open"
    field :created_by, @user_id_type

    timestamps(type: :utc_datetime)
  end

  def channels, do: @channels
  def statuses, do: @statuses

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:ticket_id, :subject, :channel, :status, :created_by])
    |> validate_required([:ticket_id, :subject, :channel])
    |> validate_length(:subject, max: 255)
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:status, @statuses)
  end

  def open(query \\ __MODULE__) do
    from(s in query, where: s.status == "open")
  end

  @doc "Serialize a conversation (optionally with its serialized replies)."
  def to_json(%__MODULE__{} = conversation, replies \\ []) do
    %{
      id: conversation.id,
      ticket_id: conversation.ticket_id,
      subject: conversation.subject,
      channel: conversation.channel,
      status: conversation.status,
      created_by: conversation.created_by,
      created_at: conversation.inserted_at,
      replies: replies
    }
  end
end
