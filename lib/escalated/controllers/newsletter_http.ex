defmodule Escalated.Controllers.NewsletterHttp do
  @moduledoc false
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Schemas.Contact
  alias Escalated.Schemas.Newsletter.{NewsletterList, NewsletterListMember}

  @pixel_png Base.decode16!(
               "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c63fcffff3f030005fe02fedccc59e70000000049454e44ae426082",
               case: :mixed
             )

  def pixel_png, do: @pixel_png

  def route_prefix, do: Escalated.config(:route_prefix, "/support")

  def newsletters_base, do: "#{route_prefix()}/admin/newsletters"

  def redirect(conn, path) do
    conn |> Phoenix.Controller.redirect(to: path) |> halt()
  end

  def abort422(conn, message) do
    conn |> put_status(422) |> Phoenix.Controller.json(%{error: message}) |> halt()
  end

  def bad_request(conn, errors) when is_map(errors) do
    conn |> put_status(400) |> Phoenix.Controller.json(%{errors: errors}) |> halt()
  end

  def discover_themes do
    dirs = [
      Application.get_env(:escalated, :newsletter_themes_dir),
      Application.app_dir(:escalated, "priv/templates/newsletter_themes")
    ]

    themes =
      dirs
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn dir ->
        if File.dir?(dir) do
          dir
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".html.eex"))
          |> Enum.map(&String.replace_suffix(&1, ".html.eex", ""))
        else
          []
        end
      end)
      |> Enum.uniq()

    if themes == [], do: ["default", "branded"], else: themes
  end

  def mail_configured? do
    is_function(Application.get_env(:escalated, :newsletter_mailer), 1)
  end

  def user_id(conn) do
    user = conn.assigns[:current_user]

    cond do
      is_map(user) and Map.has_key?(user, :id) -> Map.get(user, :id)
      is_struct(user) -> Map.get(user, :id)
      true -> nil
    end
  end

  def decode_tracked_url(encoded) when is_binary(encoded) do
    normalized = String.replace(encoded, "-", "+") |> String.replace("_", "/")
    pad = rem(byte_size(normalized), 4)
    padded = if pad == 0, do: normalized, else: normalized <> String.duplicate("=", 4 - pad)

    with {:ok, decoded} <- Base.decode64(padded),
         %URI{scheme: scheme} <- URI.parse(decoded),
         true <- scheme in ["http", "https"] do
      {:ok, decoded}
    else
      _ -> :error
    end
  end

  def decode_tracked_url(_), do: :error

  def token_from_message_id(message_id) when is_binary(message_id) do
    case Regex.run(~r/n-\d+-([A-Za-z0-9]+)@/, message_id) do
      [_, token] ->
        token

      _ ->
        local = message_id |> String.split("@") |> List.first() || ""

        case Regex.run(~r/^n-\d+-([A-Za-z0-9]+)$/, local) do
          [_, token] -> token
          _ -> ""
        end
    end
  end

  def token_from_message_id(_), do: ""

  def lists_with_counts(repo) do
    lists = repo.all(from(l in NewsletterList, select: %{id: l.id, name: l.name, kind: l.kind}))

    Enum.map(lists, fn list ->
      member_count =
        repo.one(
          from(m in NewsletterListMember, where: m.list_id == ^list.id, select: count(m.id))
        ) || 0

      opted_out =
        repo.one(
          from(m in NewsletterListMember,
            join: c in Contact,
            on: c.id == m.contact_id,
            where: m.list_id == ^list.id and not is_nil(c.marketing_opt_out_at),
            select: count(m.id)
          )
        ) || 0

      Map.merge(list, %{member_count: member_count, opted_out_count: opted_out})
    end)
  end

  def required_string(params, key, max \\ nil) do
    value = param(params, key)

    cond do
      not is_binary(value) or String.trim(value) == "" ->
        {:error, key, "#{key} is required"}

      max && String.length(value) > max ->
        {:error, key, "#{key} may not be greater than #{max} characters"}

      true ->
        {:ok, value}
    end
  end

  def optional_string(params, key, max \\ nil) do
    value = param(params, key)

    cond do
      value in [nil, ""] ->
        {:ok, nil}

      not is_binary(value) ->
        {:error, key, "#{key} must be a string"}

      max && String.length(value) > max ->
        {:error, key, "#{key} may not be greater than #{max} characters"}

      true ->
        {:ok, value}
    end
  end

  def required_integer(params, key, min \\ nil, max \\ nil) do
    value = param(params, key)

    with n when is_integer(n) <- parse_int(value),
         true <- is_nil(min) or n >= min,
         true <- is_nil(max) or n <= max do
      {:ok, n}
    else
      _ -> {:error, key, "#{key} must be an integer"}
    end
  end

  def optional_integer(params, key) do
    value = param(params, key)
    if value in [nil, ""], do: {:ok, nil}, else: required_integer(params, key)
  end

  def required_boolean(params, key) do
    value = param(params, key)

    case value do
      true -> {:ok, true}
      false -> {:ok, false}
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      "1" -> {:ok, true}
      "0" -> {:ok, false}
      1 -> {:ok, true}
      0 -> {:ok, false}
      _ -> {:error, key, "#{key} must be a boolean"}
    end
  end

  def assert_email(value, key, required \\ false) do
    cond do
      value in [nil, ""] and required -> {:error, key, "#{key} must be a valid email"}
      value in [nil, ""] -> {:ok, nil}
      valid_email?(value) -> {:ok, value}
      true -> {:error, key, "#{key} must be a valid email"}
    end
  end

  def assert_one_of(value, key, allowed) do
    if to_string(value) in allowed,
      do: {:ok, to_string(value)},
      else: {:error, key, "#{key} must be one of #{Enum.join(allowed, ", ")}"}
  end

  def optional_date_after_now(params, key) do
    value = param(params, key)

    cond do
      value in [nil, ""] ->
        {:ok, nil}

      true ->
        case parse_datetime(value) do
          {:ok, dt} ->
            if DateTime.compare(dt, DateTime.utc_now()) == :gt do
              {:ok, dt}
            else
              {:error, key, "#{key} must be a future date"}
            end

          _ ->
            {:error, key, "#{key} must be a future date"}
        end
    end
  end

  def collect_errors(results) do
    Enum.reduce(results, %{}, fn
      {:ok, _}, acc -> acc
      {:error, key, message}, acc -> Map.put(acc, to_string(key), [message])
    end)
  end

  defp param(params, key) do
    Map.get(params, key) || Map.get(params, to_string(key))
  end

  defp parse_int(v) when is_integer(v), do: v

  defp parse_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp parse_datetime(%DateTime{} = dt), do: {:ok, DateTime.truncate(dt, :second)}

  defp parse_datetime(v) when is_binary(v) do
    case DateTime.from_iso8601(v) do
      {:ok, dt, _} -> {:ok, DateTime.truncate(dt, :second)}
      _ -> :error
    end
  end

  defp parse_datetime(_), do: :error

  def valid_email?(email) when is_binary(email) do
    String.length(email) <= 320 and Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email)
  end

  def valid_email?(_), do: false
end
