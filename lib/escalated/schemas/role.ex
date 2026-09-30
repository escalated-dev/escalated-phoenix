defmodule Escalated.Schemas.Role do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}roles" do
    field :tenant_id, :string, default: ""
    field :name, :string
    field :slug, :string
    field :description, :string
    field :is_system, :boolean, default: false

    many_to_many :permissions, Escalated.Schemas.Permission,
      join_through: Escalated.Schemas.RolePermission,
      join_defaults: {Escalated.Schemas.RolePermission, :tenant_defaults, []},
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :slug, :description, :is_system])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> Escalated.Tenancy.Constraints.add_unique_constraints()
  end
end
