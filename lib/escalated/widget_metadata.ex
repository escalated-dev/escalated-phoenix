defmodule Escalated.WidgetMetadata do
  @moduledoc """
  Host parameters an embedding page sends with a widget ticket or chat as
  `metadata` (order number, plan, account id, the page URL, ...).

  They are visitor supplied, so only a flat map of short scalar values is
  kept: at most 25 entries (in key order), keys matching
  `^[A-Za-z0-9_.:-]{1,64}$`, values that are strings (trimmed, cut to 500
  characters), integers, floats or booleans. `page_url` is kept only when it
  is an http(s) URL of at most 2048 bytes. `embedded_on` is never taken from
  the page: it is set from the allowed cross-origin `Origin` header, when
  there is one.
  """

  alias Escalated.Plugs.WidgetCors

  @max_entries 25
  @max_keys 50
  @max_value_length 500
  @max_url_length 2048
  @key ~r/\A[A-Za-z0-9_.:-]{1,64}\z/

  @doc """
  Returns `{:ok, map | nil}` with the sanitised parameters (nil when nothing is
  left), or `{:error, message}` when `metadata` is present but not an object
  or has more than #{@max_keys} keys.
  """
  def from_params(%Plug.Conn{} = conn, params) when is_map(params) do
    case Map.get(params, "metadata") do
      nil ->
        {:ok, finish(%{}, conn)}

      metadata when is_map(metadata) and map_size(metadata) <= @max_keys ->
        {:ok, metadata |> clean() |> finish(conn)}

      metadata when is_map(metadata) ->
        {:error, "The metadata may not have more than #{@max_keys} keys."}

      _ ->
        {:error, "The metadata must be an object."}
    end
  end

  @doc "Answers a request whose `metadata` was rejected by `from_params/2`."
  def invalid(conn, message) do
    conn
    |> Plug.Conn.put_status(422)
    |> Phoenix.Controller.json(%{message: message, errors: %{metadata: [message]}})
  end

  defp clean(metadata) do
    metadata
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.flat_map(fn {key, value} ->
      with key when is_binary(key) <- key,
           true <- key != "embedded_on" and Regex.match?(@key, key),
           {:ok, value} <- value(value) do
        [{key, value}]
      else
        _ -> []
      end
    end)
    |> Enum.take(@max_entries)
    |> Map.new()
    |> drop_bad_page_url()
  end

  defp value(value) when is_binary(value),
    do: {:ok, value |> String.trim() |> String.slice(0, @max_value_length)}

  defp value(value) when is_integer(value) or is_float(value) or is_boolean(value),
    do: {:ok, value}

  defp value(_), do: :error

  defp drop_bad_page_url(%{"page_url" => url} = clean) do
    if web_url?(url), do: clean, else: Map.delete(clean, "page_url")
  end

  defp drop_bad_page_url(clean), do: clean

  defp web_url?(url) when is_binary(url) and byte_size(url) <= @max_url_length do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host}} when is_binary(scheme) and is_binary(host) ->
        String.downcase(scheme) in ["http", "https"] and host != ""

      _ ->
        false
    end
  end

  defp web_url?(_), do: false

  # Recorded by the server from the request's Origin header, so the page
  # cannot claim another site.
  defp finish(clean, conn) do
    clean = Map.delete(clean, "embedded_on")

    clean =
      case WidgetCors.origin(conn) do
        origin when is_binary(origin) -> Map.put(clean, "embedded_on", origin)
        _ -> clean
      end

    if map_size(clean) == 0, do: nil, else: clean
  end
end
