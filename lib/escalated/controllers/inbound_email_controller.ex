defmodule Escalated.Controllers.InboundEmailController do
  @moduledoc """
  Single ingress point for inbound-email webhooks.

  Dispatches the raw payload to the matching parser (selected via
  the `?adapter=...` query parameter or `x-escalated-adapter`
  header), then resolves the parsed message to a ticket via
  `Escalated.Services.Email.Inbound.Router`.

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

  alias Escalated.Services.Email.Inbound.Router
  alias Escalated.Schemas.Ticket

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
        options = %{inbound_secret: inbound_secret()}

        case Router.resolve_ticket(message, lookup, options) do
          %Ticket{id: id} ->
            json(conn, %{"status" => "matched", "ticket_id" => id})

          nil ->
            json(conn, %{"status" => "unmatched", "ticket_id" => nil})
        end

      {:error, _reason} ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid payload"})
    end
  end

  defp default_lookup do
    repo = Escalated.repo()

    %{
      get_ticket_by_id: fn id -> repo.get(Ticket, id) end,
      get_ticket_by_reference: fn ref -> repo.get_by(Ticket, reference: ref) end
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
