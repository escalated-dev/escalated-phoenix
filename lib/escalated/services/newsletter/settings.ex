defmodule Escalated.Services.Newsletter.Settings do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.EscalatedSetting
  alias Escalated.Services.SettingsService

  @keys %{
    "default_from" => :string,
    "default_reply_to" => :string,
    "default_theme" => :string,
    "rate_limit_per_minute" => :number,
    "batch_size" => :number,
    "tracking_enabled" => :boolean
  }

  def keys, do: Map.keys(@keys)

  def show_map do
    Map.new(keys(), fn key ->
      {String.to_atom(key), read(key)}
    end)
  end

  def read(key) when is_binary(key) do
    case SettingsService.get("newsletter.#{key}") do
      nil -> config_fallback(key)
      "" -> config_fallback(key)
      value -> cast_value(key, value)
    end
  end

  def upsert!(attrs) when is_map(attrs) do
    repo = Escalated.repo()

    for {key, type} <- @keys, key = to_string(key) do
      value = Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))

      stored =
        case type do
          :boolean ->
            if value in [true, "true", 1, "1"], do: "1", else: "0"

          _ ->
            if is_nil(value), do: "", else: to_string(value)
        end

      existing = repo.one(from(s in EscalatedSetting, where: s.key == ^"newsletter.#{key}"))

      row_attrs = %{
        key: "newsletter.#{key}",
        value: stored,
        type: Atom.to_string(type),
        group: "newsletter"
      }

      case existing do
        nil ->
          %EscalatedSetting{}
          |> EscalatedSetting.changeset(row_attrs)
          |> repo.insert!()

        row ->
          row |> EscalatedSetting.changeset(row_attrs) |> repo.update!()
      end
    end

    :ok
  end

  defp cast_value("tracking_enabled", value),
    do: value in ["1", "true", true, 1]

  defp cast_value("rate_limit_per_minute", value), do: String.to_integer(value)
  defp cast_value("batch_size", value), do: String.to_integer(value)
  defp cast_value(_, nil), do: nil
  defp cast_value(_, value), do: value

  defp config_fallback(key) do
    case key do
      "default_from" -> Application.get_env(:escalated, :newsletter_default_from)
      "default_reply_to" -> Application.get_env(:escalated, :newsletter_default_reply_to)
      "default_theme" -> Application.get_env(:escalated, :newsletter_default_theme, "default")
      "rate_limit_per_minute" -> Application.get_env(:escalated, :newsletter_rate_limit_per_minute, 60)
      "batch_size" -> Application.get_env(:escalated, :newsletter_batch_size, 50)
      "tracking_enabled" -> Application.get_env(:escalated, :newsletter_tracking_enabled, true)
      _ -> nil
    end
  end
end
