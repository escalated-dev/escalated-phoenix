defmodule Escalated.Schemas.TwoFactor do
  @moduledoc """
  Ecto schema for two-factor authentication configuration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}two_factors" do
    field :user_id, :integer
    field :method, :string, default: "totp"
    field :secret, :string
    field :recovery_codes, {:array, :string}
    field :is_enabled, :boolean, default: false
    field :verified_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(two_factor, attrs) do
    two_factor
    |> cast(attrs, [:user_id, :method, :secret, :recovery_codes, :is_enabled, :verified_at])
    |> validate_required([:user_id, :method])
  end

  @doc "Use a recovery code; returns {true, updated_codes} or {false, codes}"
  def use_recovery_code(%__MODULE__{recovery_codes: nil}, _code), do: {false, nil}
  def use_recovery_code(%__MODULE__{recovery_codes: codes}, code) do
    if code in codes do
      {true, List.delete(codes, code)}
    else
      {false, codes}
    end
  end
end
