defmodule Escalated.Schemas.CannedResponse do
  @moduledoc """
  Ecto schema for Canned Responses — reusable agent reply templates.

  Agents maintain a library of prewritten replies. Each response is either
  shared (visible to every agent) or private to its creator. Mirrors the
  laravel/rails/django ports; see the Laravel `CannedResponse` model and
  `CannedResponsePolicy` for the canonical sharing/visibility contract.

  This is distinct from a Macro (a manual one-click *action bundle*) — a
  canned response is just a stored body of text an agent can drop into a
  reply.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  @type t :: %__MODULE__{}

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}canned_responses" do
    field :title, :string
    field :body, :string
    field :category, :string
    # If true, every agent sees and may edit/delete the response.
    field :is_shared, :boolean, default: true
    # Host-app user id of the creator. Null only for system-seeded rows.
    field :created_by, @user_id_type

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(canned_response, attrs) do
    canned_response
    |> cast(attrs, [:title, :body, :category, :is_shared, :created_by])
    |> validate_required([:title, :body])
    |> validate_length(:title, max: 255)
    |> validate_length(:category, max: 100)
  end

  @doc "Only shared canned responses, title-ordered."
  def shared(query \\ __MODULE__) do
    from(c in query, where: c.is_shared == true, order_by: [asc: c.title])
  end

  @doc "Visible to a given agent: shared responses plus responses they created."
  def for_agent(query \\ __MODULE__, agent_id) do
    from(c in query,
      where: c.is_shared == true or c.created_by == ^agent_id,
      order_by: [asc: c.title]
    )
  end

  @doc "Serialize a canned response for the agent / admin frontend."
  def to_json(%__MODULE__{} = c) do
    %{
      id: c.id,
      title: c.title,
      body: c.body,
      category: c.category,
      is_shared: c.is_shared,
      created_by: c.created_by,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end
end
