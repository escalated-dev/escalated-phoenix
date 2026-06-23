defmodule Escalated.Schemas.EscalatedSetting do
  @moduledoc """
  Ecto schema for the key/value runtime settings store. Backs the
  public-ticket guest policy (mode / user_id / signup URL template)
  plus any future runtime-switchable config.

  Mirrors the escalated-dotnet EscalatedSettings model, the
  escalated-symfony EscalatedSetting entity, and the escalated-go
  `store.Settings` methods.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}settings" do
    field :key, :string
    field :value, :string
    field :type, :string
    field :group, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :type, :group])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
