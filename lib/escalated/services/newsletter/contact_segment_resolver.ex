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
  defp normalize_filter(%{rules: _} = filter), do: Map.new(filter, fn {k, v} -> {to_string(k), v} end)
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

  defp apply_metadata_rule(query, key, value) do
    encoded = Jason.encode!(value)
    path = "$." <> key

    where(
      query,
      [c],
      fragment("CAST(json_extract(?, ?) AS TEXT) = ?", c.metadata, ^path, ^encoded)
    )
  end
end
