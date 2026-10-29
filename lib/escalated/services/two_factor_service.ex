defmodule Escalated.Services.TwoFactorService do
  @moduledoc """
  Two-factor authentication (ADR 2026-10-29-configurable-access-features):
  TOTP enrolment, verification and single-use recovery codes.

  TOTP is RFC 6238 (SHA-1, 6 digits, 30 s steps) computed by `NimbleTOTP`,
  accepting one step of clock drift either side. The time step of each
  accepted code is recorded (`last_used_step`), and that step or any earlier
  one is refused afterwards, so a code works once.

  Secrets and recovery codes are stored encrypted
  (`Escalated.Types.EncryptedString`). Enforcement (the challenge, the
  required-enrolment redirect) is `Escalated.Plugs.RequireTwoFactor`, active
  only while `Escalated.AccessFeatures.two_factor?/0`.
  """

  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.TwoFactor

  @period 30
  # Steps of clock drift accepted either side of now.
  @window 1
  @recovery_code_count 8

  # ---- Policy -----------------------------------------------------------------

  @doc """
  Whether staff must enrol: the `two_factor_required` setting when an admin
  has saved it, else `config :escalated, two_factor: [required: true]` (env
  `ESCALATED_TWO_FACTOR_REQUIRED`). Only while the two-factor switch is on.
  """
  def required? do
    Escalated.AccessFeatures.two_factor?() and
      Escalated.Services.GeneralSettings.enabled?(:two_factor_required)
  end

  @doc "The install's configured default for `two_factor_required`."
  def configured_required? do
    case Keyword.fetch(options(), :required) do
      {:ok, value} -> truthy?(value)
      :error -> truthy?(System.get_env("ESCALATED_TWO_FACTOR_REQUIRED"))
    end
  end

  @doc "Whether `user` is staff without a confirmed enrolment while it is required."
  def must_enrol?(nil), do: false

  def must_enrol?(user) do
    required?() and Escalated.Permissions.agent?(user) and is_nil(confirmed_for(user))
  end

  # ---- Enrolments -------------------------------------------------------------

  @doc "The user's confirmed enrolment, or nil."
  def confirmed_for(nil), do: nil

  def confirmed_for(user) do
    case user_id(user) do
      nil ->
        nil

      id ->
        from(t in TwoFactor,
          where: t.user_id == ^id and t.is_enabled == true,
          order_by: [desc: t.id],
          limit: 1
        )
        |> repo().one()
    end
  end

  @doc "The user's pending (set up, not yet confirmed) enrolment, or nil."
  def pending_for(user) do
    from(t in TwoFactor,
      where: t.user_id == ^user_id(user) and t.is_enabled == false and not is_nil(t.secret),
      order_by: [desc: t.id],
      limit: 1
    )
    |> repo().one()
  end

  @doc """
  Starts an enrolment: replaces any pending one with a new secret and eight
  recovery codes. Returns the `otpauth://` URI and the codes, the only time
  they leave the server in plain text, or `{:error, :already_enabled}`.
  """
  def setup(user) do
    if confirmed_for(user) do
      {:error, :already_enabled}
    else
      id = user_id(user)
      secret = NimbleTOTP.secret()
      encoded = Base.encode32(secret, padding: false)
      codes = generate_recovery_codes()

      repo().transaction(fn ->
        from(t in TwoFactor, where: t.user_id == ^id and t.is_enabled == false)
        |> repo().delete_all()

        repo().insert!(%TwoFactor{
          user_id: id,
          tenant_id: Escalated.Tenancy.current_id!(),
          method: "totp",
          secret: encoded,
          recovery_codes: codes,
          is_enabled: false
        })
      end)

      {:ok, %{qr_uri: otpauth_uri(secret, user), recovery_codes: codes}}
    end
  end

  @doc """
  Confirms the pending enrolment with a code from the authenticator app.
  Returns `{:ok, recovery_codes}`, `{:error, :no_pending}` or
  `{:error, :invalid_code}`.
  """
  def confirm(user, code) do
    case pending_for(user) do
      nil ->
        {:error, :no_pending}

      pending ->
        case verify_and_consume(pending, code) do
          {:ok, consumed} ->
            consumed
            |> Ecto.Changeset.change(
              is_enabled: true,
              verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
            )
            |> repo().update!()

            {:ok, consumed.recovery_codes || []}

          :error ->
            {:error, :invalid_code}
        end
    end
  end

  @doc "Removes every enrolment of the user with `user_id`. Returns how many."
  def remove(user_id) do
    {count, _} = from(t in TwoFactor, where: t.user_id == ^user_id) |> repo().delete_all()
    count
  end

  # ---- Verification -----------------------------------------------------------

  @doc """
  Checks a TOTP `code` against the enrolment, accepting one step of drift,
  and records the step it matched. A step at or before the last one accepted
  is refused. Returns `{:ok, updated}` or `:error`.
  """
  def verify_and_consume(%TwoFactor{secret: encoded} = two_factor, code)
      when is_binary(encoded) and is_binary(code) do
    code = String.replace(code, ~r/\s+/, "")

    with true <- Regex.match?(~r/\A\d{6}\z/, code),
         {:ok, secret} <- Base.decode32(String.upcase(encoded), padding: false),
         step when is_integer(step) <- matching_step(secret, code, two_factor.last_used_step) do
      # Only moves forward, so two requests racing with the same code cannot
      # both be accepted.
      last = two_factor.last_used_step

      query =
        if is_nil(last),
          do: from(t in TwoFactor, where: t.id == ^two_factor.id and is_nil(t.last_used_step)),
          else: from(t in TwoFactor, where: t.id == ^two_factor.id and t.last_used_step == ^last)

      case repo().update_all(query, set: [last_used_step: step]) do
        {1, _} -> {:ok, %{two_factor | last_used_step: step}}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  def verify_and_consume(_two_factor, _code), do: :error

  @doc "Uses a recovery code: `{:ok, updated}` (the code removed) or `:error`."
  def use_recovery_code(%TwoFactor{} = two_factor, code) when is_binary(code) do
    case TwoFactor.use_recovery_code(two_factor, code) do
      {true, remaining} ->
        two_factor
        |> Ecto.Changeset.change(recovery_codes: remaining)
        |> repo().update()
        |> case do
          {:ok, updated} -> {:ok, updated}
          {:error, _} -> :error
        end

      {false, _} ->
        :error
    end
  end

  def use_recovery_code(_two_factor, _code), do: :error

  # The time step within the drift window whose code matches, newer than
  # `last_used`; nil when none does.
  defp matching_step(secret, code, last_used) do
    now = div(System.os_time(:second), @period)

    Enum.find((now - @window)..(now + @window), fn step ->
      (is_nil(last_used) or step > last_used) and
        Plug.Crypto.secure_compare(
          NimbleTOTP.verification_code(secret, time: step * @period, period: @period),
          code
        )
    end)
  end

  @doc "The `otpauth://` URI an authenticator app reads from a QR code."
  def otpauth_uri(secret, user) do
    issuer = Keyword.get(options(), :issuer) || "Escalated"
    account = Map.get(user, :email) || to_string(user_id(user))
    NimbleTOTP.otpauth_uri("#{issuer}:#{account}", secret, issuer: issuer)
  end

  # ---- Kept for existing callers --------------------------------------------

  @doc """
  Creates a confirmed enrolment without a code (for hosts that enrol users
  themselves). The secret is on the returned struct.
  """
  def enable(repo, user_id, method \\ "totp") do
    repo = Escalated.Tenancy.scoped_repo(repo)

    attrs = %{
      user_id: user_id,
      method: method,
      secret: Base.encode32(NimbleTOTP.secret(), padding: false),
      recovery_codes: generate_recovery_codes(),
      is_enabled: true,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    %TwoFactor{}
    |> TwoFactor.changeset(attrs)
    |> repo.insert()
  end

  @doc "Find active 2FA config for a user."
  def find_by_user(repo, user_id) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    repo.get_by(TwoFactor, user_id: user_id, is_enabled: true)
  end

  @doc "Verify a recovery code."
  def verify_recovery_code(repo, %TwoFactor{} = tf, code) do
    repo = Escalated.Tenancy.scoped_repo(repo)

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
    repo = Escalated.Tenancy.scoped_repo(repo)

    tf
    |> Ecto.Changeset.change(is_enabled: false, secret: nil, recovery_codes: nil)
    |> repo.update()
  end

  @doc "Regenerate recovery codes."
  def regenerate_recovery_codes(repo, %TwoFactor{} = tf) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    codes = generate_recovery_codes()

    tf
    |> Ecto.Changeset.change(recovery_codes: codes)
    |> repo.update()
  end

  defp generate_recovery_codes do
    Enum.map(1..@recovery_code_count, fn _ ->
      a = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
      b = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
      "#{a}-#{b}"
    end)
  end

  defp options do
    case Escalated.config(:two_factor, []) do
      opts when is_list(opts) -> opts
      opts when is_map(opts) -> Map.to_list(opts)
      _ -> []
    end
  end

  defp user_id(user) when is_map(user), do: Map.get(user, :id)
  defp user_id(_), do: nil

  defp truthy?(value), do: value in [true, 1, "1", "true", "TRUE", "True", "on", "yes"]

  defp repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())
end
