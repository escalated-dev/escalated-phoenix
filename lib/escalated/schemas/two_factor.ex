defmodule Escalated.Schemas.TwoFactor do
  @moduledoc """
  A user's TOTP enrolment. `is_enabled` is false while it is pending (set up
  but not yet confirmed with a code) and true once confirmed.

  The secret and recovery codes are stored encrypted
  (`Escalated.Types.EncryptedString`), never serialized, and redacted from
  `inspect/1`. `last_used_step` is the TOTP time step of the last code
  accepted, so that code (or an older one) cannot be used again.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Escalated.Types.EncryptedString

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}two_factors" do
    field :tenant_id, :string, default: ""
    field :user_id, @user_id_type
    field :method, :string, default: "totp"
    field :secret, EncryptedString, redact: true
    field :recovery_codes, {:array, EncryptedString}, redact: true
    field :is_enabled, :boolean, default: false
    field :verified_at, :utc_datetime
    field :last_used_step, :integer

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

  def use_recovery_code(%__MODULE__{recovery_codes: codes}, code) when is_binary(code) do
    wanted = normalize(code)

    case Enum.find(codes, &(wanted != "" and Plug.Crypto.secure_compare(normalize(&1), wanted))) do
      nil -> {false, codes}
      match -> {true, List.delete(codes, match)}
    end
  end

  def use_recovery_code(%__MODULE__{recovery_codes: codes}, _code), do: {false, codes}

  defp normalize(nil), do: ""
  defp normalize(code), do: code |> String.trim() |> String.downcase()
end
