defmodule Escalated.Schemas.SideConversationReply do
  @moduledoc """
  A reply within a `Escalated.Schemas.SideConversation`. Mirrors the
  Laravel `SideConversationReply` model.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}side_conversation_replies" do
    field :side_conversation_id, :id
    field :body, :string
    field :author_id, @user_id_type

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reply, attrs) do
    reply
    |> cast(attrs, [:side_conversation_id, :body, :author_id])
    |> validate_required([:side_conversation_id, :body])
  end

  @doc "Serialize a reply row for the frontend."
  def to_json(%__MODULE__{} = reply) do
    %{
      id: reply.id,
      side_conversation_id: reply.side_conversation_id,
      body: reply.body,
      author_id: reply.author_id,
      created_at: reply.inserted_at
    }
  end
end
