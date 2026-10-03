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
        get_ticket_by_reference: fn ref -> Ticket | nil end,
        # optional; defaults to [ticket.guest_email]
        requester_emails: fn ticket -> [String.t() | nil] end
      }

      %{
        create: fn attrs -> {:ok, Ticket} | {:error, any()} end,
        add_reply: fn ticket, attrs -> {:ok, Reply} | {:error, any()} end,
        # optional; called after an accepted reply on a resolved/closed ticket
        reopen: fn ticket -> {:ok, Ticket} | {:error, any()} end
      }

  This keeps the inbound-email module framework-agnostic and testable
  without spinning up the full `TicketService` / Ecto repo.

  ## Who a matched email may post as

  A router match is only a lookup. The email becomes a reply only when
  its `From` address (case-insensitive) is one of the ticket's requester
  addresses, and it is posted as that requester (`author_id` is the
  requester user id, or `nil` for a guest / contact). Staff identity is
  never taken from `From`. Anyone else gets a new ticket of their own:
  their mail is not dropped and does not reopen the matched ticket.
  Only an accepted reply reopens a resolved or closed ticket. See
  developer-context `domain-model/email-threading.md`.

  ## Outcomes

    * `:replied_to_existing` — router matched a ticket and the sender is
      its requester; the reply was appended via `writer.add_reply`.
    * `:created_new` — no match (or a sender who is not the requester)
      + real content; a new ticket was created via `writer.create`.
    * `:skipped` — no match but message is noise (SNS confirmation,
      fully-empty body+subject).
  """

  alias Escalated.Services.Email.Inbound.Router
  require Logger

  @type outcome :: :replied_to_existing | :created_new | :skipped

  @reopenable_statuses ~w(resolved closed)

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
          required(:get_ticket_by_reference) => (String.t() -> any() | nil),
          optional(:requester_emails) => (any() -> [String.t() | nil])
        }

  @type writer :: %{
          required(:create) => (map() -> {:ok, any()} | {:error, any()}),
          required(:add_reply) => (any(), map() -> {:ok, any()} | {:error, any()}),
          optional(:reopen) => (any() -> {:ok, any()} | {:error, any()})
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
    ticket = Router.resolve_ticket(message, lookup, options)

    case ticket && reply_author(ticket, message, lookup) do
      {:ok, author_id} ->
        reply_to_existing(message, ticket, author_id, writer)

      _ ->
        if ticket do
          Logger.info(
            "[Inbound.Service] email matched ticket ##{ticket_id(ticket)} but not its requester; opening a new ticket"
          )
        end

        create_or_skip(message, writer)
    end
  end

  @doc """
  Decide who a threaded inbound email may post as.

  Returns `{:ok, author_id}` when the `From` address (case-insensitive)
  is one of the ticket's requester addresses: the requester's user id,
  or `nil` for a guest / contact requester. Returns `:error` for anyone
  else. Staff identity is never taken from the unauthenticated `From`
  header, so an agent's address is not the requester and its mail
  becomes a new ticket.

  Requester addresses come from `lookup.requester_emails/1` when given
  (the controller resolves the guest email, the Contact's email and the
  requester user's email), else from the ticket's `guest_email`.
  """
  @spec reply_author(any(), map(), map()) :: {:ok, any()} | :error
  def reply_author(ticket, message, lookup) do
    sender = normalize_email(Map.get(message, :from_email) || Map.get(message, "from_email"))

    requester_emails =
      case Map.get(lookup, :requester_emails) do
        fun when is_function(fun, 1) -> fun.(ticket)
        _ -> [Map.get(ticket, :guest_email)]
      end

    if sender != "" and sender in Enum.map(List.wrap(requester_emails), &normalize_email/1) do
      {:ok, Map.get(ticket, :requester_id)}
    else
      :error
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

  defp create_or_skip(message, writer) do
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
  end

  defp reply_to_existing(message, ticket, author_id, writer) do
    body = message_body(message)

    reply_attrs = %{
      body: body,
      is_internal: false,
      author_id: author_id,
      author_type: "inbound_email"
    }

    with {:ok, reply} <- writer.add_reply.(ticket, reply_attrs),
         :ok <- maybe_reopen(ticket, writer) do
      {:ok,
       %{
         outcome: :replied_to_existing,
         ticket_id: ticket_id(ticket),
         reply_id: reply_id(reply),
         pending_attachment_downloads: pending_downloads(message)
       }}
    end
  end

  # Only an accepted requester reply reopens a resolved or closed ticket.
  defp maybe_reopen(ticket, writer) do
    reopen = Map.get(writer, :reopen)

    if Map.get(ticket, :status) in @reopenable_statuses and is_function(reopen, 1) do
      case reopen.(ticket) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp normalize_email(email) when is_binary(email),
    do: email |> String.trim() |> String.downcase()

  defp normalize_email(_), do: ""

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
