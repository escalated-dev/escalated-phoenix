defmodule Escalated.Schemas.RoleUser do
  @moduledoc """
  A host user holding an Escalated role. A user's permissions are the union
  of their roles' permissions (`Escalated.Permissions.list_slugs_for_user/1`).
  """
  use Ecto.Schema

  @primary_key false
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{@prefix}role_user" do
    field :tenant_id, :string, default: ""
    belongs_to :role, Escalated.Schemas.Role
    field :user_id, @user_id_type
  end
end
