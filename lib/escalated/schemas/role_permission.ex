defmodule Escalated.Schemas.RolePermission do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}role_permissions" do
    field :tenant_id, :string, default: ""
    belongs_to :role, Escalated.Schemas.Role
    belongs_to :permission, Escalated.Schemas.Permission
  end

  @doc false
  def tenant_defaults(schema, _owner) do
    struct(schema, tenant_id: Escalated.Tenancy.current_id!())
  end
end
