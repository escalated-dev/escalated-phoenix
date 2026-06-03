defmodule Escalated.Schemas.Role do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}roles" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :is_system, :boolean, default: false

    many_to_many :permissions, Escalated.Schemas.Permission,
      join_through:
        "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}role_permissions",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :slug, :description, :is_system])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
