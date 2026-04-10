defmodule Escalated.Services.TwoFactorService do
  @moduledoc "Service for managing two-factor authentication."

  alias Escalated.Schemas.TwoFactor

  @doc "Enable 2FA for a user."
  def enable(repo, user_id, method \\ "totp") do
    attrs = %{
      user_id: user_id,
      method: method,
      secret: generate_secret(),
      recovery_codes: generate_recovery_codes(),
      is_enabled: true
    }

    %TwoFactor{}
    |> TwoFactor.changeset(attrs)
    |> repo.insert()
  end

  @doc "Find active 2FA config for a user."
  def find_by_user(repo, user_id) do
    repo.get_by(TwoFactor, user_id: user_id, is_enabled: true)
  end

  @doc "Verify a recovery code."
  def verify_recovery_code(repo, %TwoFactor{} = tf, code) do
    case TwoFactor.use_recovery_code(tf, code) do
      {true, new_codes} ->
        tf
        |> Ecto.Changeset.change(recovery_codes: new_codes)
        |> repo.update()

      {false, _} ->
        {:error, :invalid_code}
    end
  end

  @doc "Disable 2FA for a user."
  def disable(repo, %TwoFactor{} = tf) do
    tf
    |> Ecto.Changeset.change(is_enabled: false, secret: nil, recovery_codes: nil)
    |> repo.update()
  end

  @doc "Regenerate recovery codes."
  def regenerate_recovery_codes(repo, %TwoFactor{} = tf) do
    codes = generate_recovery_codes()

    tf
    |> Ecto.Changeset.change(recovery_codes: codes)
    |> repo.update()
  end

  defp generate_secret(length \\ 32) do
    chars = ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    1..length
    |> Enum.map(fn _ -> Enum.random(chars) end)
    |> List.to_string()
  end

  defp generate_recovery_codes(count \\ 8) do
    Enum.map(1..count, fn _ ->
      a = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
      b = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
      "#{a}-#{b}"
    end)
  end
end
