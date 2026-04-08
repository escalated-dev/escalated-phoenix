defmodule Escalated.Schemas.ChatRoutingRule do
  @moduledoc """
  Ecto schema for chat routing rules.

  Routing rules determine how incoming chat sessions are assigned to agents.
  Each rule specifies a strategy, a list of eligible agent IDs, and a
  maximum number of concurrent chats per agent.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @strategies ~w(round_robin least_active department)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}chat_routing_rules" do
    field :name, :string
    field :strategy, :string, default: "round_robin"
    field :agent_ids, {:array, :integer}, default: []
    field :priority, :integer, default: 0
    field :max_concurrent_chats, :integer, default: 5
    field :is_active, :boolean, default: true

    belongs_to :department, Escalated.Schemas.Department

    timestamps(type: :utc_datetime)
  end

  def strategies, do: @strategies

  @doc false
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :name, :strategy, :department_id, :agent_ids,
      :priority, :max_concurrent_chats, :is_active
    ])
    |> validate_required([:name])
    |> validate_inclusion(:strategy, @strategies)
    |> validate_number(:max_concurrent_chats, greater_than: 0)
  end

  def active(query \\ __MODULE__) do
    from(r in query, where: r.is_active == true, order_by: [desc: r.priority])
  end
end
