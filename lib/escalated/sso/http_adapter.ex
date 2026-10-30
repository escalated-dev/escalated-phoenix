defmodule Escalated.Sso.HttpAdapter do
  @moduledoc """
  The `Assent.HTTPAdapter` the OAuth provider uses by default: Erlang's
  `:httpc` with the peer certificate and host name verified against the
  operating system's CA store (`:httpc.ssl_verify_host_options/1`), a
  timeout, and no redirects followed. Hosts can name another adapter with
  `config :escalated, sso: [http_adapter: ...]`.
  """
  @behaviour Assent.HTTPAdapter

  alias Assent.HTTPAdapter.HTTPResponse

  @timeout_ms 10_000

  @impl true
  def request(method, url, body, headers, _opts) do
    _ = :application.ensure_all_started(:inets)
    _ = :application.ensure_all_started(:ssl)

    headers = headers ++ [Assent.HTTPAdapter.user_agent_header()]
    {content_type, headers} = content_type(headers)
    charlist_headers = Enum.map(headers, fn {k, v} -> {to_charlist(k), to_charlist(v)} end)

    request =
      case body do
        nil -> {to_charlist(url), charlist_headers}
        body -> {to_charlist(url), charlist_headers, to_charlist(content_type), body}
      end

    http_opts =
      [timeout: @timeout_ms, connect_timeout: @timeout_ms, autoredirect: false] ++ ssl(url)

    case :httpc.request(method, request, http_opts, body_format: :binary) do
      {:ok, {{_version, status, _reason}, resp_headers, resp_body}} ->
        {:ok,
         %HTTPResponse{
           status: status,
           headers:
             Enum.map(resp_headers, fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end),
           body: resp_body
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp content_type(headers) do
    case List.keytake(headers, "content-type", 0) do
      {{_key, value}, rest} -> {value, rest}
      nil -> {"application/x-www-form-urlencoded", headers}
    end
  end

  defp ssl(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) ->
        [
          ssl:
            :httpc.ssl_verify_host_options(true) ++
              [server_name_indication: to_charlist(host)]
        ]

      _ ->
        []
    end
  end
end
