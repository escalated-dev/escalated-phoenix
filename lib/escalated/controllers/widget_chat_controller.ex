defmodule Escalated.Controllers.WidgetChatController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  import Ecto.Query
  alias Escalated.Broadcasting
  alias Escalated.Controllers.GuestAccessController, as: AccessController
  alias Escalated.Schemas.{ChatSession, Reply, SatisfactionRating}
  alias Escalated.Services.{ChatAvailabilityService, ChatSessionService, GuestAccess}

  def availability(conn, _params) do
    status = ChatAvailabilityService.get_status()
    json(conn, Map.put(status, :data, status))
  end

  def start(conn, params) do
    if Map.get(Escalated.config(:widget_settings, %{}), :enabled, true) do
      attrs = %{
        guest_name: params["name"],
        guest_email: params["email"],
        subject: params["subject"],
        message: params["message"],
        page_url: params["page_url"],
        visitor_ip: to_string(:inet.ntoa(conn.remote_ip)),
        visitor_user_agent: List.first(get_req_header(conn, "user-agent"))
      }

      case ChatSessionService.start_guest(params, attrs) do
        {:ok, ticket, session, result} ->
          token = result["guest_access_token"]

          payload = %{
            id: token,
            session_id: token,
            ticket_reference: ticket.reference,
            guest_access_token: token,
            expires_at: result["expires_at"],
            status: session.status,
            messages: []
          }

          conn |> put_status(201) |> json(Map.put(payload, :data, payload))

        {:error, reason} ->
          AccessController.error(conn, reason)
      end
    else
      conn |> put_status(403) |> json(%{error: "Widget is disabled"}) |> halt()
    end
  end

  def send_message(conn, params) do
    with {:ok, _ticket, session, _grant} <- session(conn, params),
         true <- session.status in ["waiting", "active"],
         body when is_binary(body) and byte_size(body) in 1..20_000 <- params["body"],
         {:ok, _reply} <- ChatSessionService.send_message(session, body) do
      conn |> put_status(201) |> json(%{data: %{status: "sent"}})
    else
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def messages(conn, params) do
    with {:ok, ticket, session, _} <- session(conn, params) do
      messages =
        Escalated.repo().all(
          from(r in Reply,
            where: r.ticket_id == ^ticket.id and r.is_internal == false,
            order_by: [desc: r.id],
            limit: 100
          )
        )
        |> Enum.reverse()
        |> Enum.map(
          &%{
            id: &1.id,
            body: &1.body,
            is_agent: not is_nil(&1.author_id),
            created_at: &1.inserted_at
          }
        )

      json(conn, %{
        messages: messages,
        agent: nil,
        typing: nil,
        ended: session.status in ["ended", "abandoned"]
      })
    else
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def typing(conn, params) do
    with {:ok, _, session, _} <- session(conn, params),
         true <- session.status in ["waiting", "active"] do
      Broadcasting.broadcast_chat_event("chat:typing", %{
        ticket_id: session.ticket_id,
        session_id: session.id,
        typing: true,
        is_agent: false
      })

      json(conn, %{message: "Typing updated."})
    else
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def end_session(conn, params) do
    with {:ok, _, session, _} <- session(conn, params),
         {:ok, _} <- ChatSessionService.end_session(session) do
      json(conn, %{data: %{status: "ended"}})
    else
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def rate(conn, params) do
    with {:ok, ticket, session, _} <- session(conn, params),
         true <- session.status == "ended",
         {:ok, _} <-
           %SatisfactionRating{}
           |> SatisfactionRating.changeset(%{
             ticket_id: ticket.id,
             rating: params["rating"],
             comment: params["comment"]
           })
           |> Escalated.repo().insert() do
      conn |> put_status(201) |> json(%{message: "Rating submitted."})
    else
      {:error, %Ecto.Changeset{}} -> AccessController.error(conn, :invalid)
      _ -> AccessController.error(conn, :not_found)
    end
  end

  defp session(_conn, %{"token" => token}) do
    with {:ok, ticket, grant} <- GuestAccess.resolve(token, "chat"),
         %ChatSession{} = session <- Escalated.repo().get_by(ChatSession, ticket_id: ticket.id) do
      {:ok, ticket, session, grant}
    else
      _ -> {:error, :not_found}
    end
  end

  defp session(conn, params),
    do: GuestAccess.resolve_session(params["reference"], GuestAccess.token(conn, params))
end
