defmodule Escalated.Controllers.WidgetController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Escalated.Controllers.Api.GuestTicketController
  alias Escalated.Controllers.GuestAccessController, as: AccessController
  alias Escalated.Controllers.GuestTicketView
  alias Escalated.Services.{GuestAccess, TicketService}
  alias Escalated.WidgetMetadata

  def config(conn, _params) do
    settings =
      widget_settings()
      |> Map.put(:guest_verification_required, true)
      # Tickets and chats keep host parameters sent as `metadata`.
      |> Map.put(:accepts_metadata, true)

    json(conn, Map.put(settings, :widget, settings))
  end

  @doc """
  OPTIONS on any widget path. Escalated.Plugs.WidgetCors answers CORS
  preflights before this runs; anything else reaching it gets an empty 204.
  """
  def preflight(conn, _params), do: send_resp(conn, 204, "")

  def create_ticket(conn, params) do
    with true <- widget_settings().enabled not in [false, nil],
         {:ok, metadata} <- WidgetMetadata.from_params(conn, params) do
      attrs = %{
        subject: params["subject"] || "Widget submission",
        description: params["description"],
        guest_name: params["name"],
        guest_email: params["email"],
        # The server's own `source` wins over a host parameter of that name.
        metadata: Map.merge(metadata || %{}, %{"source" => "widget"})
      }

      case TicketService.create_guest(params, attrs) do
        {:ok, ticket, result} ->
          payload =
            Map.merge(
              GuestTicketController.guest_json(ticket),
              AccessController.public_grant(result)
            )

          conn |> put_status(201) |> json(Map.put(payload, "ticket", payload))

        {:error, reason} ->
          AccessController.error(conn, reason)
      end
    else
      false -> conn |> put_status(403) |> json(%{error: "Widget is disabled"}) |> halt()
      {:error, message} -> WidgetMetadata.invalid(conn, message)
    end
  end

  def show_ticket(conn, %{"reference" => reference} = params) do
    token = GuestAccess.token(conn, params)

    with {:ok, ticket, grant} <- GuestAccess.resolve(token),
         true <- ticket.reference == reference do
      payload = GuestTicketView.correspondence(ticket, token, grant)
      json(conn, Map.put(payload, "ticket", payload))
    else
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def reply(conn, %{"reference" => reference} = params) do
    with {:ok, ticket, _} <- GuestAccess.resolve(GuestAccess.token(conn, params)),
         true <- ticket.reference == reference,
         {:ok, reply} <- TicketService.reply(ticket, %{body: params["body"], is_internal: false}) do
      conn
      |> put_status(201)
      |> json(%{reply: %{body: reply.body, created_at: reply.inserted_at}})
    else
      {:error, %Ecto.Changeset{}} -> AccessController.error(conn, :invalid)
      _ -> AccessController.error(conn, :not_found)
    end
  end

  defp widget_settings do
    Map.merge(
      %{
        enabled: true,
        title: "Contact Support",
        greeting: "How can we help you?",
        primary_color: "#4F46E5",
        fields: ~w(name email subject description),
        require_email: true
      },
      Escalated.config(:widget_settings, %{})
    )
  end
end
