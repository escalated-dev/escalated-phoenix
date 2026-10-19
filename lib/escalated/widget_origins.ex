defmodule Escalated.WidgetOrigins do
  @moduledoc """
  Decides which other sites may embed the support widget.

  The allow list is `config :escalated, widget_allowed_origins: [...]` (a list,
  or one comma separated string such as an environment variable) plus the
  admin setting `widget_allowed_origins` (one origin per line or comma
  separated). Entries are bare origins, `scheme://host[:port]` over http or
  https, or `https://*.example.com` for every subdomain of example.com (not
  example.com itself). A bare `*` is never accepted.
  """

  alias Escalated.Services.SettingsService

  @setting "widget_allowed_origins"
  @pattern ~r{\A(https?)://(\*\.)?([^/?#*\s]+?)/?\z}i

  @doc "The settings key holding the admin-managed list."
  def setting_key, do: @setting

  @doc """
  The request's Origin when it names another site, or nil for same-origin
  requests and requests without a usable Origin header.
  """
  def cross_origin(%Plug.Conn{} = conn) do
    with [origin | _] <- Plug.Conn.get_req_header(conn, "origin"),
         false <- origin in ["", "null"],
         origin when is_binary(origin) <- normalize(origin),
         false <- origin == normalize(own_origin(conn)) do
      origin
    else
      _ -> nil
    end
  end

  @doc "Whether the config list or the admin setting allows `origin`."
  def allows?(origin) when is_binary(origin), do: matches_any?(configured(), origin)
  def allows?(_), do: false

  @doc "Whether the config list alone allows `origin` (no settings read)."
  def allows_configured?(origin) when is_binary(origin),
    do: matches_any?(patterns(config_entries()), origin)

  def allows_configured?(_), do: false

  @doc "Every allowed pattern, normalised and without duplicates."
  def configured do
    patterns(config_entries() ++ split(setting()))
  end

  @doc "Splits an admin-entered list on newlines, commas and spaces."
  def split(nil), do: []
  def split(value) when is_binary(value), do: String.split(value, ~r/[\s,]+/, trim: true)
  def split(_), do: []

  @doc """
  Normalises an admin-entered origin or `*.` pattern, or returns nil when it is
  not a bare http(s) origin.
  """
  def normalize_pattern(entry) when is_binary(entry) do
    case Regex.run(@pattern, String.trim(entry)) do
      [_, scheme, wildcard, host] ->
        case normalize(String.downcase(scheme) <> "://" <> host) do
          nil -> nil
          origin when wildcard == "" -> origin
          origin -> String.replace(origin, "://", "://*.", global: false)
        end

      _ ->
        nil
    end
  end

  def normalize_pattern(_), do: nil

  defp matches_any?(patterns, origin) do
    case normalize(origin) do
      nil -> false
      origin -> Enum.any?(patterns, &matches?(&1, origin))
    end
  end

  defp matches?(pattern, origin) do
    case String.split(pattern, "://*.", parts: 2) do
      [^pattern] ->
        pattern == origin

      [scheme, suffix] ->
        case String.split(origin, "://", parts: 2) do
          [^scheme, host] ->
            String.ends_with?(host, "." <> suffix) and
              byte_size(host) > byte_size(suffix) + 1

          _ ->
            false
        end
    end
  end

  defp patterns(entries) do
    entries
    |> Enum.map(&normalize_pattern(to_string(&1)))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp config_entries do
    case Escalated.config(:widget_allowed_origins, []) do
      value when is_binary(value) -> String.split(value, ",", trim: true)
      value when is_list(value) -> value
      _ -> []
    end
  end

  defp setting do
    SettingsService.get(@setting)
  rescue
    # Without a resolved tenant (or before the settings table exists) only the
    # config list can be consulted.
    _ -> nil
  end

  # scheme://host[:port], lowercased, default ports dropped.
  defp normalize(origin) do
    with {:ok, %URI{} = uri} <- URI.new(String.trim(origin)),
         scheme when scheme in ["http", "https"] <- uri.scheme && String.downcase(uri.scheme),
         host when is_binary(host) and host != "" <- uri.host,
         nil <- uri.userinfo,
         nil <- uri.query,
         nil <- uri.fragment,
         true <- uri.path in [nil, "", "/"],
         false <- String.contains?(host, ["*", " "]) do
      host = String.downcase(host)

      case {scheme, uri.port} do
        {"http", 80} -> "http://" <> host
        {"https", 443} -> "https://" <> host
        {_, nil} -> scheme <> "://" <> host
        {_, port} -> "#{scheme}://#{host}:#{port}"
      end
    else
      _ -> nil
    end
  end

  defp own_origin(conn) do
    port =
      case {conn.scheme, conn.port} do
        {:http, 80} -> ""
        {:https, 443} -> ""
        {_, port} -> ":#{port}"
      end

    "#{conn.scheme}://#{conn.host}#{port}"
  end
end
