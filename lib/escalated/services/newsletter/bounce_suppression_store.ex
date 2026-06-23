defmodule Escalated.Services.Newsletter.BounceSuppressionStore do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.EscalatedSetting
  alias Escalated.Services.SettingsService

  @key "newsletter.suppressed_emails"

  def mark_bounced(email), do: mark(email)
  def mark_complained(email), do: mark(email)

  def is_bounced?(email) when is_binary(email) do
    email |> String.downcase() |> then(&(&1 in load()))
  end

  def filter_sendable(emails) when is_list(emails) do
    suppressed = MapSet.new(load())

    emails
    |> Enum.reject(fn email ->
      is_binary(email) and String.downcase(email) in suppressed
    end)
  end

  defp mark(email) when is_binary(email) do
    lowered = String.downcase(email)
    list = load()

    if lowered in list do
      :ok
    else
      SettingsService.set(@key, Jason.encode!(list ++ [lowered]), "newsletter")
      :ok
    end
  end

  defp load do
    case SettingsService.get(@key) do
      nil ->
        []

      value ->
        case Jason.decode(value) do
          {:ok, list} when is_list(list) -> Enum.map(list, &String.downcase(to_string(&1)))
          _ -> []
        end
    end
  end
end
