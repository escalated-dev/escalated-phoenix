defmodule Escalated.Types.EncryptedString do
  @moduledoc """
  A string stored encrypted (`Plug.Crypto.MessageEncryptor`, AES-256-GCM) and
  decrypted when read, for the two-factor secret and recovery codes.

  The key is derived from `:two_factor_secret`, or from `:guest_access_secret`
  when that is unset; either must be 32 bytes or more:

      config :escalated, two_factor_secret: System.fetch_env!("ESCALATED_TWO_FACTOR_SECRET")

  A value written before encryption (a plain base32 TOTP secret or recovery
  code, which never contain a `.`) is read as it is and encrypted the next
  time it is saved. A value that does not decrypt under the configured key
  (tampered with, or written under another key) reads as nil.
  """
  use Ecto.Type
  require Logger

  @salt "escalated two-factor"

  @impl true
  def type, do: :string

  @impl true
  def cast(value) when is_binary(value) or is_nil(value), do: {:ok, value}
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_binary(value) do
    {secret, sign} = keys!()
    {:ok, Plug.Crypto.MessageEncryptor.encrypt(value, secret, sign)}
  end

  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    if String.contains?(value, ".") do
      {secret, sign} = keys!()

      case Plug.Crypto.MessageEncryptor.decrypt(value, secret, sign) do
        {:ok, plain} ->
          {:ok, plain}

        :error ->
          Logger.warning("Escalated: a two-factor value did not decrypt under the configured key")
          {:ok, nil}
      end
    else
      {:ok, value}
    end
  end

  def load(_), do: :error

  defp keys! do
    base = Escalated.config(:two_factor_secret) || Escalated.config(:guest_access_secret)

    unless is_binary(base) and byte_size(base) >= 32 do
      raise ArgumentError,
            "Escalated two-factor needs :two_factor_secret (or :guest_access_secret), " <>
              "32 bytes or more, to encrypt secrets and recovery codes"
    end

    {Plug.Crypto.KeyGenerator.generate(base, @salt <> " encryption", length: 32),
     Plug.Crypto.KeyGenerator.generate(base, @salt <> " signing", length: 32)}
  end
end
