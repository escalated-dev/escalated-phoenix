defmodule Escalated.Controllers.Admin.SideConversationController do
  @moduledoc """
  Manage side conversations on a ticket: list, create (with an initial
  reply), add replies, and close. Mirrors the Laravel
  `SideConversationController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{SideConversation, SideConversationReply}
  alias Escalated.Services.TicketService

  def index(conn, %{"reference" => reference}) do
    case TicketService.find(reference) do
      nil -> conn |> put_status(404) |> json(%{error: "Ticket not found"})
      ticket -> json(conn, %{conversations: conversations_for(ticket)})
    end
  end

  def create(conn, %{"reference" => reference} = params) do
    repo = Escalated.repo()
    user = conn.assigns[:current_user]

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         {:ok, conversation} <- create_conversation(repo, ticket, params, user) do
      add_reply(repo, conversation.id, params["body"], user)
      conn |> put_flash(:info, "Side conversation created.") |> redirect(to: ticket_path(ticket))
    else
      nil -> conn |> put_status(404) |> json(%{error: "Ticket not found"})
      {:error, changeset} -> conn |> put_status(422) |> json(%{errors: format_errors(changeset)})
    end
  end

  def reply(conn, %{"reference" => reference, "id" => id} = params) do
    repo = Escalated.repo()
    user = conn.assigns[:current_user]

    with %SideConversation{} = conversation <- find_conversation(repo, reference, id),
         {:ok, _} <- add_reply(repo, conversation.id, params["body"], user) do
      conn
      |> put_flash(:info, "Reply added.")
      |> redirect(to: ticket_path_for(conversation, repo))
    else
      {:error, changeset} -> conn |> put_status(422) |> json(%{errors: format_errors(changeset)})
      _ -> conn |> put_status(404) |> json(%{error: "Side conversation not found"})
    end
  end

  def close(conn, %{"reference" => reference, "id" => id}) do
    repo = Escalated.repo()

    case find_conversation(repo, reference, id) do
      %SideConversation{} = conversation ->
        conversation |> SideConversation.changeset(%{status: "closed"}) |> repo.update()

        conn
        |> put_flash(:info, "Side conversation closed.")
        |> redirect(to: ticket_path_for(conversation, repo))

      _ ->
        conn |> put_status(404) |> json(%{error: "Side conversation not found"})
    end
  end

  defp find_conversation(repo, reference, id) do
    ticket = TicketService.find(reference)
    conversation = ticket && repo.get(SideConversation, id)

    if conversation && conversation.ticket_id == ticket.id, do: conversation, else: nil
  end

  defp create_conversation(repo, ticket, params, user) do
    %SideConversation{}
    |> SideConversation.changeset(%{
      ticket_id: ticket.id,
      subject: params["subject"],
      channel: params["channel"],
      status: "open",
      created_by: user && user.id
    })
    |> repo.insert()
  end

  defp add_reply(repo, conversation_id, body, user) do
    %SideConversationReply{}
    |> SideConversationReply.changeset(%{
      side_conversation_id: conversation_id,
      body: body,
      author_id: user && user.id
    })
    |> repo.insert()
  end

  defp conversations_for(ticket) do
    repo = Escalated.repo()

    conversations =
      repo.all(
        from(s in SideConversation, where: s.ticket_id == ^ticket.id, order_by: [desc: s.id])
      )

    replies_by_conversation = replies_by_conversation(repo, Enum.map(conversations, & &1.id))

    Enum.map(conversations, fn conversation ->
      replies =
        replies_by_conversation
        |> Map.get(conversation.id, [])
        |> Enum.map(&SideConversationReply.to_json/1)

      SideConversation.to_json(conversation, replies)
    end)
  end

  defp replies_by_conversation(repo, conversation_ids) do
    from(r in SideConversationReply,
      where: r.side_conversation_id in ^conversation_ids,
      order_by: [asc: r.id]
    )
    |> repo.all()
    |> Enum.group_by(& &1.side_conversation_id)
  end

  defp ticket_path_for(conversation, repo) do
    case repo.get(Escalated.Schemas.Ticket, conversation.ticket_id) do
      nil -> default_path()
      ticket -> ticket_path(ticket)
    end
  end

  defp ticket_path(ticket) do
    "#{Escalated.config(:route_prefix, "/support")}/admin/tickets/#{ticket.reference}"
  end

  defp default_path do
    "#{Escalated.config(:route_prefix, "/support")}/admin/tickets"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
