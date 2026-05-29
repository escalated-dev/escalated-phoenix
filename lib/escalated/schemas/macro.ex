defmodule Escalated.Schemas.Macro do
  @moduledoc """
  Ecto schema for Macros — agent-applied, manual one-click action bundles.

  Distinct from Workflow (admin event-driven) and Automation (admin
  time-based). See escalated-developer-context/domain-model/
  workflows-automations-macros.md.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}macros" do
    field :name, :string
    field :description, :string
    # Actions: list of %{"type" => ..., "value" => ...}
    field :actions, {:array, :map}, default: []
    # If true, all agents see and can apply.
    field :is_shared, :boolean, default: true
    # Host-app user id of the creator. Null only for system-seeded macros.
    field :created_by, @user_id_type

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(macro, attrs) do
    macro
    |> cast(attrs, [:name, :description, :actions, :is_shared, :created_by])
    |> validate_required([:name])
  end

  @doc "Visible to a given agent: shared macros plus macros they created."
  def for_agent(query \\ __MODULE__, agent_id) do
    from(m in query,
      where: m.is_shared == true or m.created_by == ^agent_id,
      order_by: [asc: m.name]
    )
  end

  @doc "Serialize for the agent / admin frontend."
  def to_json(%__MODULE__{} = m) do
    %{
      id: m.id,
      name: m.name,
      description: m.description,
      actions: m.actions,
      is_shared: m.is_shared,
      created_by: m.created_by,
      inserted_at: m.inserted_at,
      updated_at: m.updated_at
    }
  end
end
