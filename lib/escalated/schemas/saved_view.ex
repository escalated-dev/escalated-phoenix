defmodule Escalated.Schemas.SavedView do
  @moduledoc """
  Ecto schema for saved ticket views (custom queues).

  A saved view stores a set of filters that can be recalled to quickly
  filter tickets. Views can be private to a user or shared with the team.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}saved_views" do
    field :name, :string
    field :filters, :map, default: %{}
    field :user_id, :integer
    field :is_shared, :boolean, default: false
    field :position, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(view, attrs) do
    view
    |> cast(attrs, [:name, :filters, :user_id, :is_shared, :position])
    |> validate_required([:name, :user_id])
    |> validate_length(:name, max: 100)
    |> unique_constraint([:user_id, :name])
  end

  @doc "Returns views belonging to a specific user."
  def for_user(query \\ __MODULE__, user_id) do
    from(v in query, where: v.user_id == ^user_id)
  end

  @doc "Returns shared views visible to all users."
  def shared(query \\ __MODULE__) do
    from(v in query, where: v.is_shared == true)
  end

  @doc "Returns views accessible by a user (own + shared)."
  def accessible_by(query \\ __MODULE__, user_id) do
    from(v in query, where: v.user_id == ^user_id or v.is_shared == true)
  end

  @doc "Orders views by position ascending."
  def ordered(query \\ __MODULE__) do
    from(v in query, order_by: [asc: v.position, asc: v.name])
  end
end
