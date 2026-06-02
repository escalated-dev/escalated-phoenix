defmodule Escalated.Schemas.Permission do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}permissions" do
    field :slug, :string
    field :name, :string
    field :group, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(permission, attrs) do
    permission
    |> cast(attrs, [:slug, :name, :group, :description])
    |> validate_required([:slug, :name])
    |> unique_constraint(:slug)
  end
end
