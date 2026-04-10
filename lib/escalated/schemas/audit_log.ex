defmodule Escalated.Schemas.AuditLog do
  @moduledoc """
  Ecto schema for audit logging of changes across the system.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}audit_logs" do
    field :action, :string
    field :entity_type, :string
    field :entity_id, :integer
    field :performer_type, :string
    field :performer_id, :integer
    field :old_values, :map
    field :new_values, :map
    field :ip_address, :string
    field :user_agent, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(audit_log, attrs) do
    audit_log
    |> cast(attrs, [:action, :entity_type, :entity_id, :performer_type, :performer_id, :old_values, :new_values, :ip_address, :user_agent])
    |> validate_required([:action, :entity_type])
  end

  def for_entity(query \\ __MODULE__, entity_type, entity_id) do
    from(a in query, where: a.entity_type == ^entity_type and a.entity_id == ^entity_id, order_by: [desc: a.inserted_at])
  end

  def by_performer(query \\ __MODULE__, performer_type, performer_id) do
    from(a in query, where: a.performer_type == ^performer_type and a.performer_id == ^performer_id, order_by: [desc: a.inserted_at])
  end
end
