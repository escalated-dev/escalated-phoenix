defmodule Escalated.Services.Email.Inbound.Router do
  @moduledoc """
  Resolves an inbound email to an existing ticket via canonical
  Message-ID parsing + signed Reply-To verification.

  ## Resolution order (first match wins)

    1. `in_reply_to` parsed via
       `Escalated.Services.Email.MessageIdUtil.parse_ticket_id_from_message_id/1`
       — cold-start path, no DB lookup required.
    2. `references` parsed via the same helper, each id in order.
    3. Signed Reply-To on `to_email` (`reply+{id}.{hmac8}@...`)
       verified via
       `Escalated.Services.Email.MessageIdUtil.verify_reply_to/2`.
       Survives clients that strip threading headers; forged
       signatures are rejected with `Plug.Crypto.secure_compare/2`.
    4. Subject line reference tag (`[{PREFIX}-...]`).

  Mirrors the NestJS reference and the per-framework inbound-verify
  PRs plus the greenfield .NET / Spring / Go routers.

  ## Lookup contract

  The caller supplies a `lookup` map with two functions:

      %{
        get_ticket_by_id: fn id -> Ticket | nil end,
        get_ticket_by_reference: fn ref -> Ticket | nil end
      }

  This keeps the router framework-agnostic — it doesn't depend on a
  specific Ecto schema or repo.
  """

  alias Escalated.Services.Email.MessageIdUtil

  @type lookup :: %{
          required(:get_ticket_by_id) => (integer() -> any() | nil),
          required(:get_ticket_by_reference) => (String.t() -> any() | nil)
        }

  @type options :: %{
          optional(:inbound_secret) => String.t(),
          optional(:subject_pattern) => Regex.t()
        }

  @default_subject_pattern ~r/\[([A-Z]+-[0-9A-Z-]+)\]/

  @doc """
  Resolve the inbound email to an existing ticket, or `nil` when no
  match (caller should create a new ticket).
  """
  @spec resolve_ticket(map(), lookup(), options()) :: any() | nil
  def resolve_ticket(message, lookup, options \\ %{}) when is_map(message) do
    # 1 + 2. Parse canonical Message-IDs out of our own headers.
    ticket = resolve_by_header_message_ids(message, lookup)

    if is_nil(ticket) do
      # 3. Signed Reply-To on the recipient address.
      case resolve_by_signed_reply_to(message, lookup, options) do
        nil ->
          # 4. Subject-line reference tag.
          resolve_by_subject_reference(message, lookup, options)

        signed_ticket ->
          signed_ticket
      end
    else
      ticket
    end
  end

  @doc """
  Return every candidate Message-ID from the inbound headers in the
  order the mail client sent them.
  """
  @spec candidate_header_message_ids(map()) :: [String.t()]
  def candidate_header_message_ids(message) do
    []
    |> maybe_prepend_in_reply_to(message)
    |> Enum.concat(references_list(message))
  end

  # --- private ---

  defp resolve_by_header_message_ids(message, lookup) do
    message
    |> candidate_header_message_ids()
    |> Enum.find_value(fn raw ->
      case MessageIdUtil.parse_ticket_id_from_message_id(raw) do
        nil -> nil
        id -> lookup.get_ticket_by_id.(id)
      end
    end)
  end

  defp resolve_by_signed_reply_to(message, lookup, options) do
    secret = Map.get(options, :inbound_secret, "")
    to_email = Map.get(message, :to_email) || Map.get(message, "to_email")

    cond do
      secret == "" ->
        nil

      is_nil(to_email) or to_email == "" ->
        nil

      true ->
        case MessageIdUtil.verify_reply_to(to_email, secret) do
          nil -> nil
          id -> lookup.get_ticket_by_id.(id)
        end
    end
  end

  defp resolve_by_subject_reference(message, lookup, options) do
    pattern = Map.get(options, :subject_pattern, @default_subject_pattern)
    subject = Map.get(message, :subject) || Map.get(message, "subject") || ""

    case Regex.run(pattern, subject) do
      [_, reference] -> lookup.get_ticket_by_reference.(reference)
      _ -> nil
    end
  end

  defp maybe_prepend_in_reply_to(ids, message) do
    value = Map.get(message, :in_reply_to) || Map.get(message, "in_reply_to")

    case value do
      nil -> ids
      "" -> ids
      raw -> [String.trim(raw) | ids]
    end
  end

  defp references_list(message) do
    case Map.get(message, :references) || Map.get(message, "references") do
      nil -> []
      "" -> []
      raw -> raw |> String.split(~r/\s+/, trim: true)
    end
  end
end
