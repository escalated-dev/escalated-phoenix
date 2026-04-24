defmodule Escalated.Services.Email.Inbound.MailgunParser do
  @moduledoc """
  Parses Mailgun's inbound webhook payload into an
  `Escalated.Services.Email.Inbound.Message`.

  Mailgun POSTs `multipart/form-data` with snake-case field names
  (`sender` / `recipient` / `subject` / `body-plain` / `body-html` /
  `Message-Id` / `In-Reply-To` / `References`) plus a JSON-encoded
  `attachments` field. Plug's form decoder delivers these as a
  plain map, which this parser reads from directly.

  ## Notes

    * Mailgun's `from` is typically `"Full Name <email@host>"` —
      we extract the display name portion separately and fall back
      to the `sender` field for the email. Surrounding quotes on
      the display name are stripped.
    * Mailgun hosts attachment content behind a URL (large
      attachments); we carry the URL through in `download_url`.
    * Malformed attachments JSON degrades gracefully (empty list).
  """

  @behaviour Escalated.Services.Email.Inbound.Parser

  alias Escalated.Services.Email.Inbound.{InboundAttachment, Message}

  @impl true
  def name, do: "mailgun"

  @impl true
  def parse(payload) when is_map(payload) do
    from_email =
      get_field(payload, "sender") || get_field(payload, "from") || ""

    from_name = extract_from_name(get_field(payload, "from"))

    to_email =
      get_field(payload, "recipient") || get_field(payload, "To") || ""

    headers =
      %{}
      |> put_if_nonempty("Message-ID", get_field(payload, "Message-Id"))
      |> put_if_nonempty("In-Reply-To", get_field(payload, "In-Reply-To"))
      |> put_if_nonempty("References", get_field(payload, "References"))

    {:ok,
     %Message{
       from_email: from_email,
       from_name: from_name,
       to_email: to_email,
       subject: get_field(payload, "subject") || "",
       body_text: blank_to_nil(get_field(payload, "body-plain")),
       body_html: blank_to_nil(get_field(payload, "body-html")),
       message_id: blank_to_nil(get_field(payload, "Message-Id")),
       in_reply_to: blank_to_nil(get_field(payload, "In-Reply-To")),
       references: blank_to_nil(get_field(payload, "References")),
       headers: headers,
       attachments: parse_attachments(get_field(payload, "attachments"))
     }}
  end

  def parse(_), do: {:error, :unsupported_payload}

  # ----- private -----

  defp get_field(payload, key) when is_map(payload) do
    Map.get(payload, key) || Map.get(payload, String.downcase(key))
  end

  defp extract_from_name(nil), do: nil
  defp extract_from_name(""), do: nil

  defp extract_from_name(raw) when is_binary(raw) do
    case String.split(raw, "<", parts: 2) do
      [name_part, _rest] ->
        name = String.trim(name_part)

        case name do
          "" ->
            nil

          _ ->
            # Strip surrounding quotes if present.
            name
            |> String.trim_leading("\"")
            |> String.trim_trailing("\"")
            |> nil_if_empty()
        end

      _ ->
        nil
    end
  end

  defp parse_attachments(nil), do: []
  defp parse_attachments(""), do: []

  defp parse_attachments(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, entries} when is_list(entries) ->
        Enum.map(entries, &attachment_from_mailgun/1)

      _ ->
        []
    end
  end

  defp parse_attachments(_), do: []

  defp attachment_from_mailgun(entry) when is_map(entry) do
    %InboundAttachment{
      name: Map.get(entry, "name", "attachment"),
      content_type: Map.get(entry, "content-type", "application/octet-stream"),
      size_bytes: Map.get(entry, "size"),
      content: nil,
      download_url: Map.get(entry, "url")
    }
  end

  defp attachment_from_mailgun(_), do: nil

  defp put_if_nonempty(map, _key, nil), do: map
  defp put_if_nonempty(map, _key, ""), do: map
  defp put_if_nonempty(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(v), do: v
end
