defmodule Escalated.Services.Email.MessageIdUtil do
  @moduledoc """
  Pure helpers for RFC 5322 Message-ID threading and signed Reply-To
  addresses. Mirrors the NestJS reference
  `escalated-nestjs/src/services/email/message-id.ts` and the Spring /
  WordPress / .NET ports.

  ## Message-ID format

      <ticket-{ticketId}@{domain}>             initial ticket email
      <ticket-{ticketId}-reply-{replyId}@{domain}>  agent reply

  ## Signed Reply-To format

      reply+{ticketId}.{hmac8}@{domain}

  The signed Reply-To carries ticket identity even when clients strip
  our Message-ID / In-Reply-To headers — the inbound provider webhook
  verifies the 8-character HMAC-SHA256 prefix before routing a reply
  to its ticket.
  """

  @doc """
  Build an RFC 5322 Message-ID. Pass `nil` for `reply_id` on the initial
  ticket email; the `-reply-{id}` tail is appended only when `reply_id`
  is non-nil.
  """
  @spec build_message_id(integer(), integer() | nil, String.t()) :: String.t()
  def build_message_id(ticket_id, nil, domain) when is_integer(ticket_id) do
    "<ticket-#{ticket_id}@#{domain}>"
  end

  def build_message_id(ticket_id, reply_id, domain)
      when is_integer(ticket_id) and is_integer(reply_id) do
    "<ticket-#{ticket_id}-reply-#{reply_id}@#{domain}>"
  end

  @doc """
  Extract the ticket id from a Message-ID we issued. Accepts the header
  value with or without angle brackets. Returns `nil` when the input
  doesn't match our shape.
  """
  @spec parse_ticket_id_from_message_id(String.t() | nil) :: integer() | nil
  def parse_ticket_id_from_message_id(nil), do: nil
  def parse_ticket_id_from_message_id(""), do: nil

  def parse_ticket_id_from_message_id(raw) when is_binary(raw) do
    case Regex.run(~r/ticket-(\d+)(?:-reply-\d+)?@/i, raw) do
      [_, id_str] -> String.to_integer(id_str)
      _ -> nil
    end
  end

  def parse_ticket_id_from_message_id(_), do: nil

  @doc """
  Build a signed Reply-To address of the form
  `reply+{ticket_id}.{hmac8}@{domain}`.
  """
  @spec build_reply_to(integer(), String.t(), String.t()) :: String.t()
  def build_reply_to(ticket_id, secret, domain)
      when is_integer(ticket_id) and is_binary(secret) and is_binary(domain) do
    "reply+#{ticket_id}.#{sign(ticket_id, secret)}@#{domain}"
  end

  @doc """
  Verify a reply-to address (full `local@domain` or just the local part).
  Returns the ticket id on match, `nil` otherwise. Uses constant-time
  comparison on the HMAC prefix.
  """
  @spec verify_reply_to(String.t() | nil, String.t()) :: integer() | nil
  def verify_reply_to(nil, _), do: nil
  def verify_reply_to("", _), do: nil

  def verify_reply_to(address, secret) when is_binary(address) and is_binary(secret) do
    local =
      case String.split(address, "@", parts: 2) do
        [l, _] -> l
        [l] -> l
      end

    case Regex.run(~r/^reply\+(\d+)\.([a-f0-9]{8})$/i, local) do
      [_, id_str, sig] ->
        ticket_id = String.to_integer(id_str)
        expected = sign(ticket_id, secret)

        if Plug.Crypto.secure_compare(String.downcase(expected), String.downcase(sig)) do
          ticket_id
        end

      _ ->
        nil
    end
  end

  def verify_reply_to(_, _), do: nil

  # 8-character HMAC-SHA256 prefix over the ticket id.
  defp sign(ticket_id, secret) do
    :crypto.mac(:hmac, :sha256, secret, Integer.to_string(ticket_id))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 8)
  end
end
