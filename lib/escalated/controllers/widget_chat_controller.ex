defmodule Escalated.Controllers.WidgetChatController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  import Ecto.Query
  alias Escalated.Broadcasting
  alias Escalated.Controllers.GuestAccessController, as: AccessController
  alias Escalated.Controllers.GuestTicketView
  alias Escalated.Schemas.{ChatSession, Reply, SatisfactionRating}
  alias Escalated.Services.{ChatAvailabilityService, ChatSessionService, GuestAccess}
  alias Escalated.{WidgetDepartments, WidgetMetadata}

  def availability(conn, _params) do
    status = ChatAvailabilityService.get_status()
    json(conn, Map.put(status, :data, status))
  end

  def start(conn, params) do
    with true <-
           Map.get(Escalated.config(:widget_settings, %{}), :enabled, true) not in [false, nil],
         {:ok, metadata} <- WidgetMetadata.from_params(conn, params) do
      attrs = %{
        guest_name: params["name"],
        guest_email: params["email"],
        subject: params["subject"],
        message: params["message"],
        department_id: WidgetDepartments.resolve(params["department_id"]),
        page_url: params["page_url"],
        metadata: metadata,
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
            messages: [],
            agent: agent(session)
          }

          conn |> put_status(201) |> json(Map.put(payload, :data, payload))

        {:error, reason} ->
          AccessController.error(conn, reason)
      end
    else
      false -> conn |> put_status(403) |> json(%{error: "Widget is disabled"}) |> halt()
      {:error, message} -> WidgetMetadata.invalid(conn, message)
    end
  end

  # As in escalated-laravel: an unknown or expired chat grant is 404; a chat
  # that has ended refuses messages, typing and a second end with 422, and
  # rating waits for the end (422).
  def send_message(conn, params) do
    with {:ok, _ticket, session, _grant} <- session(conn, params),
         :open <- open(session),
         {:body, body} when is_binary(body) and byte_size(body) in 1..20_000 <-
           {:body, params["body"]},
         {:ok, _reply} <- ChatSessionService.send_message(session, body) do
      conn |> put_status(201) |> json(%{data: %{status: "sent"}})
    else
      :ended -> ended(conn, "Chat has ended.")
      {:body, _} -> ended(conn, "The message is required.")
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def messages(conn, params) do
    with {:ok, ticket, session, _} <- session(conn, params) do
      replies =
        Escalated.repo().all(
          from(r in Reply,
            where: r.ticket_id == ^ticket.id and r.is_internal == false,
            order_by: [desc: r.id],
            limit: 100
          )
        )
        |> Enum.reverse()

      agents = GuestTicketView.agent_names([session.agent_id | Enum.map(replies, & &1.author_id)])

      messages =
        Enum.map(
          replies,
          &%{
            id: &1.id,
            body: &1.body,
            is_agent: GuestTicketView.agent?(&1),
            author: %{name: GuestTicketView.author_name(&1, ticket, agents)},
            created_at: &1.inserted_at
          }
        )

      json(conn, %{
        messages: messages,
        agent: agent(session, agents),
        typing: nil,
        ended: session.status in ["ended", "abandoned"]
      })
    else
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def typing(conn, params) do
    with {:ok, _, session, _} <- session(conn, params),
         :open <- open(session) do
      Broadcasting.broadcast_chat_event("chat:typing", %{
        ticket_id: session.ticket_id,
        session_id: session.id,
        typing: true,
        is_agent: false
      })

      json(conn, %{message: "Typing updated."})
    else
      :ended -> ended(conn, "Chat has ended.")
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def end_session(conn, params) do
    with {:ok, _, session, _} <- session(conn, params),
         :open <- open(session),
         {:ok, _} <- ChatSessionService.end_session(session) do
      json(conn, %{data: %{status: "ended"}})
    else
      :ended -> ended(conn, "Chat has already ended.")
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def rate(conn, params) do
    with {:ok, ticket, session, _} <- session(conn, params),
         {:ended, true} <- {:ended, session.status == "ended"},
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
      {:ended, false} -> ended(conn, "Chat must be ended before rating.")
      {:error, %Ecto.Changeset{}} -> AccessController.error(conn, :invalid)
      _ -> AccessController.error(conn, :not_found)
    end
  end

  defp open(%ChatSession{status: status}) when status in ["waiting", "active"], do: :open
  defp open(_session), do: :ended

  defp ended(conn, message), do: conn |> put_status(422) |> json(%{message: message})

  # The agent who joined the chat, as the widget shows them, or nil.
  defp agent(session, agents \\ nil)
  defp agent(%ChatSession{agent_id: nil}, _), do: nil

  defp agent(%ChatSession{agent_id: id}, agents) do
    agents = agents || GuestTicketView.agent_names([id])
    %{name: Map.get(agents, id) || "Support"}
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
