defmodule Escalated.Rendering.Paginator do
  @moduledoc """
  Laravel's length-aware paginator, which is the shape the shared list pages
  read: `data`, `current_page`, `last_page`, `per_page`, `total`, `from`,
  `to`, the page URLs and `links`.

  `paginate/4` pages a list already in memory; `paginate_query/4` pages an
  Ecto query with a count and an offset query. Either way rows are mapped with
  `fun` only for the page sent.
  """
  import Ecto.Query, only: [exclude: 2, limit: 2, offset: 2]

  @default_per_page 15
  @max_per_page 100

  @doc "Pages a list. `params` may carry `page` and `per_page`."
  def paginate(rows, params, path, fun \\ & &1) when is_list(rows) do
    {page, per_page} = page_params(params)
    total = length(rows)

    data =
      rows
      |> Enum.drop((page - 1) * per_page)
      |> Enum.take(per_page)
      |> Enum.map(fun)

    build(data, page, per_page, total, path, params)
  end

  @doc "Pages an Ecto query on `repo`."
  def paginate_query(query, repo, params, path, fun \\ & &1) do
    {page, per_page} = page_params(params)
    total = repo.aggregate(exclude(query, :order_by), :count)

    data =
      query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> repo.all()
      |> Enum.map(fun)

    build(data, page, per_page, total, path, params)
  end

  defp build(data, page, per_page, total, path, params) do
    last_page = max(1, div(total + per_page - 1, per_page))
    from = if data == [], do: nil, else: (page - 1) * per_page + 1
    to = if data == [], do: nil, else: (page - 1) * per_page + length(data)
    url = fn n -> page_url(path, params, n) end

    %{
      data: data,
      current_page: page,
      last_page: last_page,
      per_page: per_page,
      total: total,
      from: from,
      to: to,
      path: path,
      first_page_url: url.(1),
      last_page_url: url.(last_page),
      next_page_url: if(page < last_page, do: url.(page + 1)),
      prev_page_url: if(page > 1, do: url.(page - 1)),
      links: links(page, last_page, url)
    }
  end

  defp links(page, last_page, url) do
    previous = %{url: if(page > 1, do: url.(page - 1)), label: "&laquo; Previous", active: false}
    next = %{url: if(page < last_page, do: url.(page + 1)), label: "Next &raquo;", active: false}

    pages =
      Enum.map(1..last_page, fn n -> %{url: url.(n), label: to_string(n), active: n == page} end)

    [previous | pages] ++ [next]
  end

  defp page_url(path, params, n) do
    query =
      params
      |> Map.drop(["page"])
      |> Enum.filter(fn {_k, v} -> is_binary(v) or is_number(v) end)
      |> Map.new()
      |> Map.put("page", n)

    path <> "?" <> URI.encode_query(query)
  end

  defp page_params(params) do
    page = positive_int(params["page"], 1)
    per_page = params["per_page"] |> positive_int(@default_per_page) |> min(@max_per_page)
    {page, per_page}
  end

  defp positive_int(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end

  defp positive_int(_value, default), do: default
end
