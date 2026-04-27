defmodule Escalated.Services.Email.Inbound.AttachmentDownloader do
  @moduledoc """
  Fetches provider-hosted attachments surfaced by
  `Escalated.Services.Email.Inbound.Service.process/4` in the
  `:pending_attachment_downloads` list and persists them as
  `Escalated.Schemas.Attachment` rows tied to a ticket (and
  optionally a reply).

  Mailgun hosts larger attachments behind a URL instead of inlining
  them in the webhook payload; host apps run this in a background
  worker after `Service.process/4` returns, so the webhook response
  can go back to the provider immediately regardless of download
  latency.

  ## Wire-up

  Pass a `storage` function-map (mirroring the Service's lookup/writer
  contract) so the module stays Ecto-free and testable:

      %{
        put: fn filename, content, content_type ->
          {:ok, "/path/on/disk"} | {:error, reason}
        end
      }

  Plus a `writer` for persisting the Attachment row:

      %{
        create_attachment: fn attrs -> {:ok, attachment} | {:error, reason} end
      }

  ## Options

    * `:http_client` — a `{module, fun}` tuple or mfa that accepts
      `(method, url, headers)` and returns
      `{:ok, %{status: integer, body: binary, headers: list}} | {:error, reason}`.
      Defaults to a thin wrapper over `:httpc` from the Erlang stdlib
      so the module has no external HTTP client dependency.
    * `:max_bytes` — reject attachments larger than this size.
      `0` (default) disables the check.
    * `:basic_auth` — `{username, password}` tuple attached to each
      request. Typical use for Mailgun:
      `{"api", System.get_env("MAILGUN_API_KEY")}`.
  """

  alias Escalated.Services.Email.Inbound.Service

  require Logger

  @type pending :: Service.pending_attachment()

  @type storage :: %{
          required(:put) =>
            (String.t(), binary(), String.t() ->
               {:ok, String.t()} | {:error, any()})
        }

  @type writer :: %{
          required(:create_attachment) => (map() -> {:ok, any()} | {:error, any()})
        }

  @type options :: %{
          optional(:http_client) => {module(), atom()} | mfa(),
          optional(:max_bytes) => non_neg_integer(),
          optional(:basic_auth) => {String.t(), String.t()}
        }

  @type result :: %{
          pending: pending(),
          persisted: any() | nil,
          error: any() | nil
        }

  @doc """
  Download one pending attachment and persist it. Returns
  `{:ok, attachment}` or `{:error, reason}`.
  """
  @spec download(pending(), integer(), integer() | nil, storage(), writer(), options()) ::
          {:ok, any()} | {:error, any()}
  def download(pending, ticket_id, reply_id, storage, writer, options \\ %{})
      when is_map(pending) do
    url = Map.get(pending, :download_url) || Map.get(pending, "download_url")

    cond do
      is_nil(url) or url == "" ->
        {:error, :missing_download_url}

      true ->
        do_download(pending, url, ticket_id, reply_id, storage, writer, options)
    end
  end

  @doc """
  Download a batch of pending attachments. Continues past
  per-attachment failures so a single bad URL doesn't block the rest;
  returns a list of `%{pending, persisted, error}` maps, one per input.
  """
  @spec download_all([pending()], integer(), integer() | nil, storage(), writer(), options()) ::
          [result()]
  def download_all(pending_list, ticket_id, reply_id, storage, writer, options \\ %{})
      when is_list(pending_list) do
    Enum.map(pending_list, fn p ->
      case download(p, ticket_id, reply_id, storage, writer, options) do
        {:ok, attachment} -> %{pending: p, persisted: attachment, error: nil}
        {:error, reason} -> %{pending: p, persisted: nil, error: reason}
      end
    end)
  end

  @doc """
  Strip path separators so a crafted attachment name like
  `"../../etc/passwd"` can't escape the storage root. Falls back to
  `"attachment"` when the input is unusable.
  """
  @spec safe_filename(String.t() | nil) :: String.t()
  def safe_filename(name)
  def safe_filename(nil), do: "attachment"
  def safe_filename(""), do: "attachment"

  def safe_filename(name) when is_binary(name) do
    base = name |> String.replace("\\", "/") |> String.trim() |> Path.basename()

    case base do
      "" -> "attachment"
      "." -> "attachment"
      ".." -> "attachment"
      other -> other
    end
  end

  # ---------- private ----------

  defp do_download(pending, url, ticket_id, reply_id, storage, writer, options) do
    headers = build_headers(options)

    with {:ok, %{status: status, body: body, headers: resp_headers}} <-
           fetch(url, headers, options),
         :ok <- check_status(status),
         :ok <- check_size(body, options),
         {filename, content_type} <- resolve_metadata(pending, resp_headers),
         {:ok, path} <- storage.put.(filename, body, content_type) do
      attrs = %{
        original_filename: filename,
        mime_type: content_type,
        size: byte_size(body),
        storage_key: path,
        storage_backend: Map.get(storage, :backend_name, "local"),
        ticket_id: ticket_id,
        reply_id: reply_id
      }

      case writer.create_attachment.(attrs) do
        {:ok, attachment} ->
          Logger.info(
            "[AttachmentDownloader] persisted #{filename} (#{byte_size(body)} bytes) for ticket ##{ticket_id}"
          )

          {:ok, attachment}

        {:error, reason} ->
          {:error, {:persist_failed, reason}}
      end
    end
  end

  defp fetch(url, headers, options) do
    case Map.get(options, :http_client) do
      nil -> default_fetch(url, headers)
      {mod, fun} -> apply(mod, fun, [:get, url, headers])
      {mod, fun, args} -> apply(mod, fun, [:get, url, headers | args])
    end
  end

  defp default_fetch(url, headers) do
    # Wrap :httpc — stdlib, no external dep. Starts the inets app so
    # :httpc is available even if the host didn't pre-start it.
    _ = :application.ensure_all_started(:inets)
    _ = :application.ensure_all_started(:ssl)

    charlist_url = String.to_charlist(url)

    charlist_headers =
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    case :httpc.request(:get, {charlist_url, charlist_headers}, [], body_format: :binary) do
      {:ok, {{_version, status, _reason}, resp_headers, body}} ->
        normalized =
          Enum.map(resp_headers, fn {k, v} -> {to_string(k), to_string(v)} end)

        {:ok, %{status: status, body: body, headers: normalized}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp build_headers(options) do
    case Map.get(options, :basic_auth) do
      {username, password} ->
        token = Base.encode64("#{username}:#{password}")
        [{"authorization", "Basic #{token}"}]

      _ ->
        []
    end
  end

  defp check_status(status) when status in 200..299, do: :ok
  defp check_status(status), do: {:error, {:http_status, status}}

  defp check_size(body, options) do
    case Map.get(options, :max_bytes, 0) do
      0 -> :ok
      max when byte_size(body) > max -> {:error, {:too_large, byte_size(body), max}}
      _ -> :ok
    end
  end

  defp resolve_metadata(pending, resp_headers) do
    filename =
      pending
      |> Map.get(:name)
      |> Kernel.||(Map.get(pending, "name"))
      |> safe_filename()

    content_type =
      pending_content_type(pending) ||
        header_value(resp_headers, "content-type") ||
        "application/octet-stream"

    {filename, content_type}
  end

  defp pending_content_type(pending) do
    case Map.get(pending, :content_type) || Map.get(pending, "content_type") do
      nil -> nil
      "" -> nil
      ct -> ct
    end
  end

  defp header_value(headers, name) do
    downcased = String.downcase(name)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == downcased, do: to_string(v)
    end)
  end
end
