defmodule Escalated.Services.Email.Inbound.Service do
  @moduledoc """
  Orchestrates the full inbound email pipeline:

      parser output → router resolution → reply-on-existing or
      create-new-ticket

  Called by `Escalated.Controllers.InboundEmailController` after the
  parser normalizes the provider payload. Mirrors the NestJS
  reference `InboundRouterService` and the .NET / Spring / Go ports.

  ## Lookup + write contracts

  Pass `lookup` and `writer` function maps so the service stays
  agnostic of which repo / TicketService the host uses:

      %{
        get_ticket_by_id: fn id -> Ticket | nil end,
        get_ticket_by_reference: fn ref -> Ticket | nil end
      }

      %{
        create: fn attrs -> {:ok, Ticket} | {:error, any()} end,
        add_reply: fn ticket, attrs -> {:ok, Reply} | {:error, any()} end
      }

  This keeps the inbound-email module framework-agnostic and testable
  without spinning up the full `TicketService` / Ecto repo.

  ## Outcomes

    * `:replied_to_existing` — router matched a ticket; the reply was
      appended via `writer.add_reply`.
    * `:created_new` — no match + real content; a new ticket was
      created via `writer.create`.
    * `:skipped` — no match but message is noise (SNS confirmation,
      fully-empty body+subject).
  """

  alias Escalated.Services.Email.Inbound.Router
  require Logger

  @type outcome :: :replied_to_existing | :created_new | :skipped

  @type pending_attachment :: %{
          name: String.t(),
          content_type: String.t(),
          size_bytes: integer() | nil,
          download_url: String.t()
        }

  @type process_result :: %{
          outcome: outcome(),
          ticket_id: integer() | nil,
          reply_id: integer() | nil,
          pending_attachment_downloads: [pending_attachment()]
        }

  @type lookup :: %{
          required(:get_ticket_by_id) => (integer() -> any() | nil),
          required(:get_ticket_by_reference) => (String.t() -> any() | nil)
        }

  @type writer :: %{
          required(:create) => (map() -> {:ok, any()} | {:error, any()}),
          required(:add_reply) => (any(), map() -> {:ok, any()} | {:error, any()})
        }

  @type options :: %{
          optional(:inbound_secret) => String.t(),
          optional(:subject_pattern) => Regex.t()
        }

  @doc """
  Process a parsed inbound message end-to-end.
  """
  @spec process(map(), lookup(), writer(), options()) ::
          {:ok, process_result()} | {:error, any()}
  def process(message, lookup, writer, options \\ %{}) when is_map(message) do
    case Router.resolve_ticket(message, lookup, options) do
      nil ->
        if noise_email?(message) do
          {:ok,
           %{
             outcome: :skipped,
             ticket_id: nil,
             reply_id: nil,
             pending_attachment_downloads: []
           }}
        else
          create_new_ticket(message, writer)
        end

      ticket ->
        reply_to_existing(message, ticket, writer)
    end
  end

  @doc """
  Predicate for messages we should skip rather than create a new
  ticket from (SNS confirmations, empty body+subject).
  """
  @spec noise_email?(map()) :: boolean()
  def noise_email?(message) do
    from = Map.get(message, :from_email) || Map.get(message, "from_email") || ""
    subject = Map.get(message, :subject) || Map.get(message, "subject") || ""
    body = message_body(message)

    cond do
      String.downcase(from) == "no-reply@sns.amazonaws.com" -> true
      String.trim(subject) == "" and String.trim(body) == "" -> true
      true -> false
    end
  end

  # ---------- private ----------

  defp reply_to_existing(message, ticket, writer) do
    body = message_body(message)

    reply_attrs = %{
      body: body,
      is_internal: false,
      author_id: nil,
      author_type: "inbound_email"
    }

    case writer.add_reply.(ticket, reply_attrs) do
      {:ok, reply} ->
        {:ok,
         %{
           outcome: :replied_to_existing,
           ticket_id: ticket_id(ticket),
           reply_id: reply_id(reply),
           pending_attachment_downloads: pending_downloads(message)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_new_ticket(message, writer) do
    subject =
      case Map.get(message, :subject) || Map.get(message, "subject") do
        nil -> "(no subject)"
        "" -> "(no subject)"
        s -> s
      end

    attrs = %{
      subject: subject,
      description: message_body(message),
      guest_name: Map.get(message, :from_name) || Map.get(message, "from_name"),
      guest_email: Map.get(message, :from_email) || Map.get(message, "from_email"),
      priority: "medium"
    }

    case writer.create.(attrs) do
      {:ok, ticket} ->
        Logger.info("[Inbound.Service] created ticket ##{ticket_id(ticket)} from inbound email")

        {:ok,
         %{
           outcome: :created_new,
           ticket_id: ticket_id(ticket),
           reply_id: nil,
           pending_attachment_downloads: pending_downloads(message)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp message_body(message) do
    body_text = Map.get(message, :body_text) || Map.get(message, "body_text")
    body_html = Map.get(message, :body_html) || Map.get(message, "body_html")

    cond do
      is_binary(body_text) and body_text != "" -> body_text
      is_binary(body_html) -> body_html
      true -> ""
    end
  end

  defp pending_downloads(message) do
    attachments = Map.get(message, :attachments) || Map.get(message, "attachments") || []

    attachments
    |> Enum.filter(&provider_hosted?/1)
    |> Enum.map(&to_pending_download/1)
  end

  defp provider_hosted?(a) do
    url = Map.get(a, :download_url) || Map.get(a, "download_url")
    content = Map.get(a, :content) || Map.get(a, "content")
    is_binary(url) and url != "" and (is_nil(content) or content == "")
  end

  defp to_pending_download(a) do
    %{
      name: Map.get(a, :name) || Map.get(a, "name"),
      content_type: Map.get(a, :content_type) || Map.get(a, "content_type"),
      size_bytes: Map.get(a, :size_bytes) || Map.get(a, "size_bytes"),
      download_url: Map.get(a, :download_url) || Map.get(a, "download_url")
    }
  end

  defp ticket_id(%{id: id}), do: id
  defp ticket_id(_), do: nil

  defp reply_id(%{id: id}), do: id
  defp reply_id(_), do: nil
end
