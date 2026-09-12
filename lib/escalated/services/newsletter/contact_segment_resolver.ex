defmodule Escalated.Services.Newsletter.ContactSegmentResolver do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.Contact
  alias Escalated.Schemas.Newsletter.{NewsletterList, NewsletterListMember}

  @allowed_fields ~w(email name user_id marketing_opt_out_at inserted_at updated_at)
  @allowed_ops ~w(= != < > <= >= like)

  def resolve(%NewsletterList{} = list) do
    if list.kind == "static" do
      member_contact_ids(list.id)
    else
      list.filter_json |> normalize_filter() |> apply_filter() |> pluck_ids()
    end
  end

  def resolve_sendable(%NewsletterList{} = list) do
    if list.kind == "static" do
      ids = member_contact_ids(list.id)

      if ids == [] do
        []
      else
        from(c in Contact,
          where: c.id in ^ids and is_nil(c.marketing_opt_out_at),
          select: c.id
        )
        |> Escalated.repo().all()
      end
    else
      list.filter_json
      |> normalize_filter()
      |> apply_filter()
      |> where([c], is_nil(c.marketing_opt_out_at))
      |> pluck_ids()
    end
  end

  def count_matches(filter) when is_map(filter) or is_nil(filter) do
    filter |> normalize_filter() |> apply_filter() |> Escalated.repo().aggregate(:count)
  end

  defp member_contact_ids(list_id) do
    from(m in NewsletterListMember, where: m.list_id == ^list_id, select: m.contact_id)
    |> Escalated.repo().all()
  end

  defp pluck_ids(query) do
    query |> select([c], c.id) |> Escalated.repo().all()
  end

  defp normalize_filter(nil), do: %{"rules" => []}
  defp normalize_filter(%{"rules" => _} = filter), do: filter

  defp normalize_filter(%{rules: _} = filter),
    do: Map.new(filter, fn {k, v} -> {to_string(k), v} end)

  defp normalize_filter(_), do: %{"rules" => []}

  defp apply_filter(filter) do
    Enum.reduce(filter["rules"] || [], Contact, fn rule, query ->
      apply_rule(query, rule)
    end)
  end

  defp apply_rule(query, rule) when is_map(rule) do
    field = rule["field"] || rule[:field]
    op = to_string(rule["op"] || rule[:op] || "=")
    value = rule["value"] || rule[:value]

    cond do
      is_nil(field) or field == "" ->
        query

      String.starts_with?(to_string(field), "metadata.") ->
        key = String.replace_prefix(to_string(field), "metadata.", "")
        apply_metadata_rule(query, key, value)

      true ->
        apply_column_rule(query, to_string(field), op, value)
    end
  end

  defp apply_rule(query, _), do: query

  defp apply_column_rule(query, field, op, value) do
    if field in @allowed_fields and op in @allowed_ops do
      col = String.to_existing_atom(field)

      case op do
        "=" -> where(query, [c], field(c, ^col) == ^value)
        "!=" -> where(query, [c], field(c, ^col) != ^value)
        "<" -> where(query, [c], field(c, ^col) < ^value)
        ">" -> where(query, [c], field(c, ^col) > ^value)
        "<=" -> where(query, [c], field(c, ^col) <= ^value)
        ">=" -> where(query, [c], field(c, ^col) >= ^value)
        "like" -> where(query, [c], like(field(c, ^col), ^"%#{value}%"))
      end
    else
      query
    end
  rescue
    ArgumentError -> query
  end

  # Reading a key out of a JSON column is the one place this module cannot stay
  # in portable Ecto. json_extract/2 is SQLite's spelling and SQLite's alone --
  # PostgreSQL has no such function, so every metadata rule raised there, and
  # PostgreSQL is what nearly every Phoenix host runs. MySQL spells it
  # JSON_EXTRACT and returns a quoted JSON scalar like SQLite does; PostgreSQL's
  # ->> returns the text already unquoted, so the two sides are compared
  # differently on purpose.
  defp apply_metadata_rule(query, key, value) do
    case json_dialect() do
      :postgres ->
        where(query, [c], fragment("? ->> ? = ?", c.metadata, ^key, ^to_text(value)))

      :mysql ->
        where(
          query,
          [c],
          fragment(
            "CAST(JSON_EXTRACT(?, ?) AS CHAR) = ?",
            c.metadata,
            ^json_path(key),
            ^Jason.encode!(value)
          )
        )

      :sqlite ->
        where(
          query,
          [c],
          fragment(
            "CAST(json_extract(?, ?) AS TEXT) = ?",
            c.metadata,
            ^json_path(key),
            ^Jason.encode!(value)
          )
        )
    end
  end

  defp json_path(key), do: "$." <> key

  # ->> yields text, so a JSON string arrives without its quotes and a number
  # arrives as its digits. Encoding through Jason and stripping the quotes keeps
  # every other type (booleans, numbers) spelled the way JSON spells it.
  defp to_text(value) when is_binary(value), do: value
  defp to_text(value), do: Jason.encode!(value)

  defp json_dialect do
    case Escalated.repo().__adapter__() do
      Ecto.Adapters.Postgres -> :postgres
      Ecto.Adapters.MyXQL -> :mysql
      _ -> :sqlite
    end
  end
end
