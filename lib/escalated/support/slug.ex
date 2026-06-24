defmodule Escalated.Support.Slug do
  @moduledoc """
  Shared URL-slug generation (knowledge-base articles, categories, …).
  """

  @doc """
  Turn a value into a URL slug: lowercased, runs of non-alphanumerics
  collapsed to single hyphens, trimmed. Returns `fallback` when the
  result would be empty.
  """
  def slugify(value, fallback \\ "item") do
    slug =
      value
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    if slug == "", do: fallback, else: slug
  end
end
