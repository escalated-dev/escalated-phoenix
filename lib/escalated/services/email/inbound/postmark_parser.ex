defmodule Escalated.Services.Email.Inbound.InboundAttachment do
  @moduledoc """
  Single attachment on an inbound email. Providers either inline the
  content (small attachments) or supply a URL to download it from
  (larger provider-hosted attachments).
  """

  defstruct [:name, :content_type, :size_bytes, :content, :download_url]
end

defmodule Escalated.Services.Email.Inbound.PostmarkParser do
  @moduledoc """
  Parses Postmark's inbound webhook payload into an
  `Escalated.Services.Email.Inbound.Message`.

  Postmark POSTs a JSON body with `FromFull` / `ToFull` / `Subject`
  / `TextBody` / `HtmlBody` / `Headers` / `Attachments` fields.

  Add additional providers (Mailgun, SES) by implementing
  `Escalated.Services.Email.Inbound.Parser` — the controller picks
  the matching parser by `name/0`.
  """

  @behaviour Escalated.Services.Email.Inbound.Parser

  alias Escalated.Services.Email.Inbound.{InboundAttachment, Message}

  @impl true
  def name, do: "postmark"

  @impl true
  def parse(payload) when is_map(payload) do
    from_full = Map.get(payload, "FromFull") || %{}
    from_email = Map.get(from_full, "Email") || Map.get(payload, "From") || ""
    from_name = Map.get(from_full, "Name") || Map.get(payload, "FromName")

    to_email =
      Map.get(payload, "OriginalRecipient") ||
        first_to_email(payload) ||
        Map.get(payload, "To") ||
        ""

    headers = extract_headers(payload)

    {:ok,
     %Message{
       from_email: from_email,
       from_name: blank_to_nil(from_name),
       to_email: to_email,
       subject: Map.get(payload, "Subject") || "",
       body_text: blank_to_nil(Map.get(payload, "TextBody")),
       body_html: blank_to_nil(Map.get(payload, "HtmlBody")),
       message_id:
         first_nonempty(Map.get(payload, "MessageID"), Map.get(headers, "Message-ID")),
       in_reply_to: Map.get(headers, "In-Reply-To"),
       references: Map.get(headers, "References"),
       headers: headers,
       attachments: extract_attachments(payload)
     }}
  end

  def parse(_), do: {:error, :unsupported_payload}

  # ----- private helpers -----

  defp first_to_email(%{"ToFull" => entries}) when is_list(entries) do
    Enum.find_value(entries, nil, fn
      %{"Email" => email} when is_binary(email) and email != "" -> email
      _ -> nil
    end)
  end

  defp first_to_email(_), do: nil

  defp extract_headers(%{"Headers" => entries}) when is_list(entries) do
    Enum.reduce(entries, %{}, fn
      %{"Name" => name, "Value" => value}, acc when is_binary(name) and is_binary(value) ->
        Map.put(acc, name, value)

      _, acc ->
        acc
    end)
  end

  defp extract_headers(_), do: %{}

  defp extract_attachments(%{"Attachments" => entries}) when is_list(entries) do
    Enum.map(entries, &attachment_from_postmark/1)
  end

  defp extract_attachments(_), do: []

  defp attachment_from_postmark(entry) do
    %InboundAttachment{
      name: Map.get(entry, "Name", "attachment"),
      content_type: Map.get(entry, "ContentType", "application/octet-stream"),
      size_bytes: Map.get(entry, "ContentLength"),
      content: decode_base64(Map.get(entry, "Content")),
      download_url: Map.get(entry, "ContentURL")
    }
  end

  defp decode_base64(nil), do: nil
  defp decode_base64(""), do: nil

  defp decode_base64(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, bin} ->
        bin

      :error ->
        case Base.decode64(value, padding: false) do
          {:ok, bin} -> bin
          :error -> nil
        end
    end
  end

  defp first_nonempty(nil, b), do: b
  defp first_nonempty("", b), do: b
  defp first_nonempty(a, _), do: a

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
