defmodule Escalated.Services.MentionService do
  @moduledoc "Service for extracting and processing @mentions in replies"

  @mention_regex ~r/@(\w+(?:\.\w+)*)/

  def extract_mentions(nil), do: []
  def extract_mentions(""), do: []
  def extract_mentions(text) when is_binary(text) do
    @mention_regex
    |> Regex.scan(text)
    |> Enum.map(fn [_, username] -> username end)
    |> Enum.uniq()
  end

  def extract_username_from_email(email) when is_binary(email) do
    email |> String.split("@") |> List.first() |> Kernel.||("")
  end
  def extract_username_from_email(_), do: ""
end
