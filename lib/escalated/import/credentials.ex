defmodule Escalated.Import.Credentials do
  @moduledoc """
  Seals an import source's credentials for the two places they rest: the
  wizard's session, from a tested connection until the import starts, and the
  import job's `credentials` column until the run ends or is cancelled.

  The key is derived from `:import_secret`, or from `:guest_access_secret`
  (which a verified-guest install already sets) when that is unset.
  """

  @salt "escalated import credentials"

  @doc "Encrypts a credentials map."
  def seal(credentials) when is_map(credentials) do
    {secret, sign} = keys!()
    Plug.Crypto.MessageEncryptor.encrypt(Jason.encode!(credentials), secret, sign)
  end

  @doc "Decrypts what `seal/1` produced; nil when absent, tampered with or sealed under another key."
  def open(nil), do: nil
  def open(""), do: nil

  def open(sealed) when is_binary(sealed) do
    {secret, sign} = keys!()

    with {:ok, json} <- Plug.Crypto.MessageEncryptor.decrypt(sealed, secret, sign),
         {:ok, %{} = credentials} <- Jason.decode(json) do
      credentials
    else
      _ -> nil
    end
  end

  def open(_), do: nil

  defp keys! do
    base = Escalated.config(:import_secret) || Escalated.config(:guest_access_secret)

    unless is_binary(base) and byte_size(base) >= 32 do
      raise ArgumentError,
            "Escalated imports need :import_secret (or :guest_access_secret), 32 bytes or more, to encrypt source credentials"
    end

    {Plug.Crypto.KeyGenerator.generate(base, @salt <> " encryption", length: 32),
     Plug.Crypto.KeyGenerator.generate(base, @salt <> " signing", length: 32)}
  end
end
