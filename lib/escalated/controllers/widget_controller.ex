defmodule Escalated.Controllers.WidgetController do
  @moduledoc """
  Public-facing controller for the embeddable support widget.

  Provides endpoints for:
  - Retrieving widget configuration/settings
  - Creating tickets from the widget
  - Fetching ticket status by guest token
  - Adding replies via guest token
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Services.TicketService
  alias Escalated.Schemas.{Ticket, Reply}
  import Ecto.Query

  @doc """
  Returns the widget configuration (branding, allowed fields, etc.).
  """
  def config(conn, _params) do
    settings = widget_settings()

    json(conn, %{
      widget: %{
        enabled: settings.enabled,
        title: settings.title,
        greeting: settings.greeting,
        primary_color: settings.primary_color,
        fields: settings.fields,
        require_email: settings.require_email
      }
    })
  end

  @doc """
  Creates a new ticket from the widget (public, unauthenticated).
  """
  def create_ticket(conn, params) do
    settings = widget_settings()

    unless settings.enabled do
      conn
      |> put_status(403)
      |> json(%{error: "Widget is disabled"})
      |> halt()
    end

    guest_token = generate_guest_token()

    attrs = %{
      subject: params["subject"] || "Widget submission",
      description: params["description"] || "",
      guest_name: params["name"],
      guest_email: params["email"],
      guest_token: guest_token,
      requester_type: "guest",
      metadata: %{"source" => "widget"}
    }

    case TicketService.create(attrs) do
      {:ok, ticket} ->
        conn
        |> put_status(201)
        |> json(%{
          ticket: %{
            reference: ticket.reference,
            guest_token: ticket.guest_token,
            status: ticket.status,
            subject: ticket.subject
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  Fetches a ticket's status using the guest token.
  """
  def show_ticket(conn, %{"reference" => reference, "guest_token" => token}) do
    repo = Escalated.repo()

    case repo.get_by(Ticket, reference: reference, guest_token: token) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      ticket ->
        replies =
          repo.all(
            from(r in Reply,
              where: r.ticket_id == ^ticket.id and r.is_internal == false,
              order_by: [asc: r.inserted_at]
            )
          )

        json(conn, %{
          ticket: %{
            reference: ticket.reference,
            subject: ticket.subject,
            status: ticket.status,
            created_at: ticket.inserted_at && DateTime.to_iso8601(ticket.inserted_at)
          },
          replies:
            Enum.map(replies, fn r ->
              %{
                body: r.body,
                created_at: r.inserted_at && DateTime.to_iso8601(r.inserted_at)
              }
            end)
        })
    end
  end

  @doc """
  Adds a reply to a ticket using the guest token.
  """
  def reply(conn, %{"reference" => reference, "guest_token" => token, "body" => body}) do
    repo = Escalated.repo()

    case repo.get_by(Ticket, reference: reference, guest_token: token) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      ticket ->
        case TicketService.reply(ticket, %{body: body, is_internal: false}) do
          {:ok, reply} ->
            conn
            |> put_status(201)
            |> json(%{
              reply: %{
                body: reply.body,
                created_at: reply.inserted_at && DateTime.to_iso8601(reply.inserted_at)
              }
            })

          {:error, changeset} ->
            conn
            |> put_status(422)
            |> json(%{errors: format_errors(changeset)})
        end
    end
  end

  # Private

  defp widget_settings do
    defaults = %{
      enabled: true,
      title: "Contact Support",
      greeting: "How can we help you?",
      primary_color: "#4F46E5",
      fields: ~w(name email subject description),
      require_email: true
    }

    configured = Escalated.config(:widget_settings, %{})

    Map.merge(defaults, configured)
  end

  defp generate_guest_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
