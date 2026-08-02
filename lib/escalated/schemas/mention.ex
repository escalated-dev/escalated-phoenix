defmodule Escalated.Schemas.Mention do
  @moduledoc """
  Ecto schema for an @mention of a host user inside an internal note.

  Mirrors the Laravel `Mention` model: a mention records that `user_id` was
  named in `reply_id`. `read_at` tracks the mention notification's read state
  (nil until the mentioned user acknowledges it). Unique per `(reply_id,
  user_id)` so the same person named twice in one note yields one mention.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}mentions" do
    field :user_id, @user_id_type
    field :read_at, :utc_datetime

    belongs_to :reply, Escalated.Schemas.Reply

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:reply_id, :user_id, :read_at])
    |> validate_required([:reply_id, :user_id])
    |> unique_constraint([:reply_id, :user_id])
  end

  @doc "Scope mentions belonging to a single host user."
  def for_user(query \\ __MODULE__, user_id) do
    from(m in query, where: m.user_id == ^user_id)
  end

  @doc "Scope to unread mentions (no `read_at`)."
  def unread(query \\ __MODULE__) do
    from(m in query, where: is_nil(m.read_at))
  end

  @doc "Most recent mentions first."
  def recent(query \\ __MODULE__) do
    from(m in query, order_by: [desc: m.inserted_at])
  end

  @doc "Serialize a mention row for the agent frontend."
  def to_json(%__MODULE__{} = mention) do
    %{
      id: mention.id,
      reply_id: mention.reply_id,
      user_id: mention.user_id,
      read_at: mention.read_at,
      created_at: mention.inserted_at
    }
  end
end
