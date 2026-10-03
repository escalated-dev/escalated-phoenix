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

  Paths 1, 2 and 4 use values anyone can guess or copy: Message-IDs
  are deterministic from the ticket id and references are sequential.
  Once an `inbound_secret` is configured (so outbound mail carries the
  signed Reply-To) only path 3 identifies a ticket; mail without a
  valid signature resolves to `nil`. Without a secret, paths 1, 2 and 4
  remain as a compatibility mode. Either way a match is only a lookup:
  `Escalated.Services.Email.Inbound.Service` decides whether the sender
  may post on it. See developer-context `domain-model/email-threading.md`.

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
    if inbound_secret(options) == "" do
      resolve_unsigned(message, lookup, options)
    else
      # 3. With a secret configured, only the signed Reply-To counts.
      resolve_by_signed_reply_to(message, lookup, options)
    end
  end

  @doc """
  The configured inbound secret from `options`, or `""` when unset.
  """
  @spec inbound_secret(options()) :: String.t()
  def inbound_secret(options), do: Map.get(options, :inbound_secret) || ""

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

  # Compatibility mode for hosts without an inbound secret.
  defp resolve_unsigned(message, lookup, options) do
    # 1 + 2. Parse canonical Message-IDs out of our own headers, then
    # 4. the subject-line reference tag.
    resolve_by_header_message_ids(message, lookup) ||
      resolve_by_subject_reference(message, lookup, options)
  end

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
    secret = inbound_secret(options)
    to_email = Map.get(message, :to_email) || Map.get(message, "to_email")

    cond do
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
