defmodule Escalated.Services.SettingsService do
  @moduledoc """
  Key/value runtime settings store. Used by the public-ticket guest
  policy (three keys: mode / user_id / signup URL template) and any
  other runtime-switchable config a host app wants to toggle without
  a redeploy.

  Empty string on missing key so callers can chain a default with
  `get_or_default/2` instead of checking `:ok` / `:error` tuples.

  Mirrors the Symfony + .NET + Go SettingsService APIs.
  """
  import Ecto.Query
  alias Escalated.Schemas.EscalatedSetting

  @spec get(String.t()) :: String.t() | nil
  def get(key) when is_binary(key) do
    repo = Escalated.repo()

    case repo.one(from s in EscalatedSetting, where: s.key == ^key, select: s.value) do
      nil -> nil
      "" -> nil
      value -> value
    end
  end

  @spec get_or_default(String.t(), String.t()) :: String.t()
  def get_or_default(key, default) when is_binary(key) and is_binary(default) do
    case get(key) do
      nil -> default
      value -> value
    end
  end

  @doc """
  Upsert a key/value (optionally tagged with a `group`). Returns the
  inserted/updated row on success or the changeset error on failure.
  """
  @spec set(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, EscalatedSetting} | {:error, Ecto.Changeset.t()}
  def set(key, value, group \\ nil) when is_binary(key) do
    repo = Escalated.repo()

    existing =
      from(s in EscalatedSetting, where: s.key == ^key)
      |> repo.one()

    attrs = %{key: key, value: value, group: group}

    case existing do
      nil ->
        %EscalatedSetting{}
        |> EscalatedSetting.changeset(attrs)
        |> repo.insert()

      %EscalatedSetting{} = row ->
        row
        |> EscalatedSetting.changeset(attrs)
        |> repo.update()
    end
  end

  @spec delete(String.t()) :: :ok | {:error, Ecto.Changeset.t()}
  def delete(key) when is_binary(key) do
    repo = Escalated.repo()

    case repo.one(from s in EscalatedSetting, where: s.key == ^key) do
      nil ->
        :ok

      row ->
        repo.delete(row)
        |> case do
          {:ok, _} -> :ok
          err -> err
        end
    end
  end
end
