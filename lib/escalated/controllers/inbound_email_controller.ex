defmodule Escalated.Controllers.InboundEmailController do
  @moduledoc """
  Single ingress point for inbound-email webhooks.

  Dispatches the raw payload to the matching parser (selected via
  the `?adapter=...` query parameter or `x-escalated-adapter`
  header), then resolves the parsed message to a ticket via
  `Escalated.Services.Email.Inbound.Router`.

  ## Threading

  Because the shared secret is required here, outbound mail carries the
  signed Reply-To and only that address links an inbound email to a
  ticket. A linked email becomes a reply only when it comes from the
  ticket's requester (the guest email, the Contact's email, or the
  requester user's email) and is posted as that requester; anything
  else opens a new ticket. Lookups run through `Escalated.repo/0` and
  `Escalated.user_repo/0`, so with tenancy enabled they are scoped to
  the tenant the host's pipeline resolved for this request.

  ## Authentication

  Guarded by a constant-time shared-secret check on the
  `x-escalated-inbound-secret` header — hosts configure this via
  `config :escalated, email_inbound_secret: "..."` (reused for
  signed Reply-To verification, so the key pair is symmetric).

  ## Parser discovery

  Host apps wire parsers via application config:

      config :escalated, inbound_parsers: [
        Escalated.Services.Email.Inbound.PostmarkParser
      ]

  Defaults to `[PostmarkParser]` when unset.

  ## Responses

    * `200 OK` — `%{"status" => "matched" | "unmatched", "ticket_id" => id | nil}`
    * `401 Unauthorized` — secret mismatch
    * `400 Bad Request` — unknown adapter / invalid payload
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Schemas.{Contact, Ticket}
  alias Escalated.Services.Email.Inbound.Service
  alias Escalated.Services.TicketService

  @default_parsers [Escalated.Services.Email.Inbound.PostmarkParser]

  def inbound(conn, params) do
    case verify_secret(conn) do
      :ok ->
        handle_authorized(conn, params)

      :error ->
        conn
        |> put_status(401)
        |> json(%{error: "missing or invalid inbound secret"})
    end
  end

  # ---------- private ----------

  defp handle_authorized(conn, params) do
    adapter =
      Map.get(params, "adapter") ||
        get_req_header(conn, "x-escalated-adapter") |> List.first()

    if adapter in [nil, ""] do
      conn
      |> put_status(400)
      |> json(%{error: "missing adapter"})
    else
      case Enum.find(parsers(), &(&1.name() == adapter)) do
        nil ->
          conn
          |> put_status(400)
          |> json(%{error: "unknown adapter: #{adapter}"})

        parser ->
          dispatch_to_parser(conn, parser, params)
      end
    end
  end

  defp dispatch_to_parser(conn, parser, params) do
    # Phoenix has already JSON-decoded the body into params; we
    # pass it straight through for the parser to map.
    case parser.parse(params) do
      {:ok, message} ->
        lookup = default_lookup()
        writer = default_writer()
        options = %{inbound_secret: inbound_secret()}

        case Service.process(message, lookup, writer, options) do
          {:ok, result} ->
            json(conn, %{
              "status" => status_string(result.outcome),
              "outcome" => Atom.to_string(result.outcome),
              "ticket_id" => result.ticket_id,
              "reply_id" => result.reply_id,
              "pending_attachment_downloads" => result.pending_attachment_downloads
            })

          {:error, _reason} ->
            conn
            |> put_status(500)
            |> json(%{error: "processing failed"})
        end

      {:error, _reason} ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid payload"})
    end
  end

  defp status_string(:replied_to_existing), do: "matched"
  defp status_string(:created_new), do: "created"
  defp status_string(:skipped), do: "skipped"

  defp default_lookup do
    repo = Escalated.repo()

    %{
      get_ticket_by_id: fn id -> repo.get(Ticket, id) end,
      get_ticket_by_reference: fn ref -> repo.get_by(Ticket, reference: ref) end,
      requester_emails: &requester_emails(repo, &1)
    }
  end

  # Every address that identifies the ticket's requester: the inline guest
  # email, the Contact's email (verified guest tickets carry only a
  # contact), and the requester user's email.
  defp requester_emails(repo, ticket) do
    [ticket.guest_email, contact_email(repo, ticket), requester_user_email(ticket)]
  end

  defp contact_email(_repo, %{contact_id: nil}), do: nil

  defp contact_email(repo, %{contact_id: contact_id}) do
    case repo.get(Contact, contact_id) do
      %Contact{email: email} -> email
      _ -> nil
    end
  end

  defp requester_user_email(%{requester_id: nil}), do: nil
  defp requester_user_email(%{requester_type: "guest"}), do: nil

  defp requester_user_email(%{requester_id: requester_id}) do
    case Escalated.config(:user_schema) do
      nil ->
        nil

      user_schema ->
        case Escalated.user_repo().get(user_schema, requester_id) do
          %{email: email} -> email
          _ -> nil
        end
    end
  end

  defp default_writer do
    %{
      create: fn attrs -> TicketService.create(attrs) end,
      add_reply: fn ticket, attrs -> TicketService.reply(ticket, attrs) end,
      reopen: fn ticket ->
        TicketService.transition_status(ticket, "reopened", actor_id: ticket.requester_id)
      end
    }
  end

  defp parsers, do: Application.get_env(:escalated, :inbound_parsers, @default_parsers)

  defp inbound_secret, do: Application.get_env(:escalated, :email_inbound_secret, "") || ""

  defp verify_secret(conn) do
    expected = inbound_secret()
    provided = conn |> get_req_header("x-escalated-inbound-secret") |> List.first()

    cond do
      expected == "" ->
        :error

      is_nil(provided) ->
        :error

      Plug.Crypto.secure_compare(expected, provided) ->
        :ok

      true ->
        :error
    end
  end
end
