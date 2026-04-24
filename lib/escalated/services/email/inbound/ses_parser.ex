defmodule Escalated.Services.Email.Inbound.SESParser do
  @moduledoc """
  Parses AWS SES inbound mail delivered via SNS HTTP subscription.
  SES receipt rules publish to an SNS topic; host apps subscribe via
  HTTP and SNS POSTs the envelope to the unified
  `/support/webhook/email/inbound?adapter=ses` webhook.

  ## Envelope types

    * `"SubscriptionConfirmation"` — one-time on subscription setup.
      Returns `{:error, {:ses_subscription_confirmation, details}}` so
      the inbound controller can surface the `subscribe_url` that the
      host must GET out-of-band to activate the subscription. Callers
      can match on the tuple to distinguish setup requests from parse
      failures.
    * `"Notification"` — the actual inbound delivery. The SNS `Message`
      field is a JSON-encoded SES notification with `mail.commonHeaders`
      (from/to/subject) and a base64-encoded raw MIME `content` field
      (when the receipt rule action is `SNS` with `BASE64` encoding).

  ## Body extraction

  Best-effort: single-part `text/plain` + `text/html` plus
  `multipart/alternative` bodies are decoded from the raw MIME
  content when supplied. Missing content leaves `:body_text` +
  `:body_html` `nil` — the router still resolves via threading
  metadata so matched replies work regardless.
  """

  @behaviour Escalated.Services.Email.Inbound.Parser

  alias Escalated.Services.Email.Inbound.Message

  @impl true
  def name, do: "ses"

  @impl true
  def parse(payload) when is_map(payload) do
    case Map.get(payload, "Type") do
      "SubscriptionConfirmation" ->
        {:error,
         {:ses_subscription_confirmation,
          %{
            topic_arn: Map.get(payload, "TopicArn", ""),
            subscribe_url: Map.get(payload, "SubscribeURL", ""),
            token: Map.get(payload, "Token", "")
          }}}

      "Notification" ->
        parse_notification(payload)

      other ->
        {:error, {:unsupported_sns_envelope, other}}
    end
  end

  def parse(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, decoded} -> parse(decoded)
      {:error, _} = err -> err
    end
  end

  def parse(_), do: {:error, :unsupported_payload}

  # ---------- private ----------

  defp parse_notification(envelope) do
    with message_json when is_binary(message_json) and message_json != "" <-
           Map.get(envelope, "Message", ""),
         {:ok, notification} <- Jason.decode(message_json) do
      build_message(notification)
    else
      "" -> {:error, :missing_message}
      nil -> {:error, :missing_message}
      {:error, reason} -> {:error, {:invalid_message_json, reason}}
    end
  end

  defp build_message(notification) do
    mail = Map.get(notification, "mail") || %{}
    common = Map.get(mail, "commonHeaders") || %{}

    {from_email, from_name} = parse_first_address_list(Map.get(common, "from"))
    {to_email, _} = parse_first_address_list(Map.get(common, "to"))

    subject = Map.get(common, "subject") || ""
    headers = extract_headers(mail)

    message_id =
      blank_to_nil(Map.get(common, "messageId")) || Map.get(headers, "Message-ID")

    in_reply_to =
      blank_to_nil(Map.get(common, "inReplyTo")) || Map.get(headers, "In-Reply-To")

    references =
      blank_to_nil(Map.get(common, "references")) || Map.get(headers, "References")

    {body_text, body_html} = extract_body(Map.get(notification, "content"))

    {:ok,
     %Message{
       from_email: from_email,
       from_name: from_name,
       to_email: to_email,
       subject: subject,
       body_text: body_text,
       body_html: body_html,
       message_id: message_id,
       in_reply_to: in_reply_to,
       references: references,
       headers: headers,
       attachments: []
     }}
  end

  # SES's `commonHeaders.from` / `.to` are arrays of RFC 5322
  # strings. Returns {email, name|nil} from the first usable entry.
  defp parse_first_address_list(list) when is_list(list) do
    list
    |> Enum.find(fn s -> is_binary(s) and String.trim(s) != "" end)
    |> case do
      nil -> {"", nil}
      raw -> parse_rfc5322_address(raw)
    end
  end

  defp parse_first_address_list(_), do: {"", nil}

  # Minimal RFC 5322 display-name parser for `Name <addr@host>` and
  # bare `addr@host` shapes — the two SES commonly emits.
  defp parse_rfc5322_address(raw) do
    raw = String.trim(raw)

    # Shape: `"?Name"? <addr@host>` — display name is optional.
    case Regex.run(~r/^\s*(?:"?([^<"]*?)"?\s*)?<([^>]+)>\s*$/, raw) do
      [_full, name, email] ->
        {String.trim(email), blank_to_nil(String.trim(name))}

      _ ->
        # Treat as a bare address.
        {raw, nil}
    end
  end

  defp extract_headers(mail) do
    case Map.get(mail, "headers") do
      list when is_list(list) ->
        Enum.reduce(list, %{}, fn
          %{"name" => name, "value" => value}, acc
          when is_binary(name) and is_binary(value) ->
            Map.put(acc, name, value)

          _, acc ->
            acc
        end)

      _ ->
        %{}
    end
  end

  defp extract_body(nil), do: {nil, nil}
  defp extract_body(""), do: {nil, nil}

  defp extract_body(content_b64) when is_binary(content_b64) do
    with {:ok, raw} <- Base.decode64(content_b64, ignore: :whitespace),
         {:ok, headers, body} <- split_headers(raw) do
      content_type = Map.get(headers, "content-type", "text/plain")
      transfer_enc = Map.get(headers, "content-transfer-encoding", "7bit")

      cond do
        String.starts_with?(String.downcase(content_type), "multipart/") ->
          walk_multipart(body, content_type)

        String.starts_with?(String.downcase(content_type), "text/html") ->
          {nil, decode_body(body, transfer_enc)}

        true ->
          {decode_body(body, transfer_enc), nil}
      end
    else
      _ -> {nil, nil}
    end
  end

  defp split_headers(raw) do
    case String.split(raw, ~r/\r?\n\r?\n/, parts: 2) do
      [header_block, body] ->
        {:ok, parse_header_block(header_block), body}

      _ ->
        {:error, :no_header_body_split}
    end
  end

  defp parse_header_block(block) do
    block
    |> String.split(~r/\r?\n/)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          Map.put(acc, String.downcase(String.trim(name)), String.trim(value))

        _ ->
          acc
      end
    end)
  end

  defp walk_multipart(body, content_type) do
    case extract_boundary(content_type) do
      nil ->
        {nil, nil}

      boundary ->
        parts = split_multipart(body, boundary)

        Enum.reduce(parts, {nil, nil}, fn part, {text, html} ->
          case split_headers(part) do
            {:ok, part_headers, part_body} ->
              part_type = Map.get(part_headers, "content-type", "")
              part_enc = Map.get(part_headers, "content-transfer-encoding", "7bit")
              decoded = decode_body(String.trim(part_body), part_enc)

              cond do
                String.starts_with?(String.downcase(part_type), "text/plain") and is_nil(text) ->
                  {decoded, html}

                String.starts_with?(String.downcase(part_type), "text/html") and is_nil(html) ->
                  {text, decoded}

                true ->
                  {text, html}
              end

            _ ->
              {text, html}
          end
        end)
    end
  end

  defp extract_boundary(content_type) do
    case Regex.run(~r/boundary\s*=\s*"?([^";\s]+)"?/i, content_type) do
      [_, boundary] -> boundary
      _ -> nil
    end
  end

  defp split_multipart(body, boundary) do
    delimiter = "--" <> boundary

    body
    |> String.split(delimiter)
    # Drop the preamble (before the first delimiter) and the
    # closing marker (`--` at the end).
    |> Enum.drop(1)
    |> Enum.reject(&(String.trim(&1) == "--" or String.trim(&1) == ""))
    |> Enum.map(&String.trim_leading(&1, "\r\n"))
    |> Enum.map(&String.trim_leading(&1, "\n"))
  end

  defp decode_body(body, transfer_enc) do
    case String.downcase(String.trim(transfer_enc)) do
      "quoted-printable" -> decode_quoted_printable(body)
      "base64" -> case Base.decode64(body, ignore: :whitespace) do
        {:ok, decoded} -> decoded
        :error -> body
      end
      _ -> body
    end
  end

  defp decode_quoted_printable(body) do
    body
    |> String.replace(~r/=\r?\n/, "")
    |> (fn stripped ->
          Regex.replace(~r/=([0-9A-Fa-f]{2})/, stripped, fn _match, hex ->
            <<String.to_integer(hex, 16)>>
          end)
        end).()
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: s
end
