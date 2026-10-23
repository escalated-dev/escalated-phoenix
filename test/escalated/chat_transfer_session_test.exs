defmodule Escalated.ChatTransferSessionTest do
  @moduledoc """
  Transferring a live chat from the agent ticket page. The shared frontend
  posts `{"agent_id"}` or `{"department_id"}` to escalated-laravel's
  `escalated.admin.chat.transfer` with the ChatSession's id (the ticket page's
  `chat_session_id`); in Phoenix that name maps to
  `POST /agent/chat/:session/transfer`. The older ticket-id route
  `POST /agent/chat/sessions/:id/transfer` keeps working.
  """
  use Escalated.PageCase

  import Ecto.Query

  alias Escalated.Schemas.{ChatSession, Department, Ticket}
  alias Escalated.Test.{GuestAccessHelpers, Router, WidgetEmbedRouter}

  @host "https://help.example.com"
  @shop "https://shop.example.com"
  @email "visitor@example.test"

  defp repo, do: Escalated.repo()

  setup do
    GuestAccessHelpers.configure()
    keys = [:widget_allowed_origins, :widget_settings, :rate_limit_backend]
    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :widget_allowed_origins, [@shop])
    Application.delete_env(:escalated, :widget_settings)
    Application.delete_env(:escalated, :rate_limit_backend)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "transfers the chat named by the ticket page's chat_session_id to another agent" do
    # The chat's session id must differ from its ticket id, so a route that
    # read the ticket id would not find this chat. The two come from separate
    # sequences whose distance depends on what earlier tests inserted (MySQL
    # keeps auto-increment values after a rolled-back test), so extra ended
    # sessions on a decoy chat move the session sequence until they differ.
    {_decoy_token, decoy} = start_chat()
    {ticket, session} = chat_with_distinct_ids(decoy)
    refute session.id == ticket.id

    page = agent(:get, "/support/agent/tickets/#{ticket.reference}", nil, inertia: true)
    assert page.status == 200, page.resp_body
    chat_session_id = Jason.decode!(page.resp_body)["props"]["ticket"]["chat_session_id"]
    assert chat_session_id == session.id

    conn = agent(:post, "/support/agent/chat/#{chat_session_id}/transfer", %{"agent_id" => 2})
    assert conn.status == 200, conn.resp_body
    body = Jason.decode!(conn.resp_body)
    assert body["message"] == "Chat transferred."
    assert body["session"]["id"] == session.id

    assert repo().get!(ChatSession, session.id).agent_id == 2
    assert repo().get!(Ticket, ticket.id).assigned_to == 2

    # The decoy chat is untouched.
    assert repo().get_by!(ChatSession, ticket_id: decoy.id, status: "waiting").agent_id == nil
  end

  test "the ChatActionBar body {type, id} is read on the session-id route" do
    {_token, ticket} = accepted_chat()
    session = repo().get_by!(ChatSession, ticket_id: ticket.id)

    conn =
      agent(:post, "/support/agent/chat/#{session.id}/transfer", %{"type" => "agent", "id" => 2})

    assert conn.status == 200, conn.resp_body
    assert repo().get!(ChatSession, session.id).agent_id == 2
  end

  test "transferring to a department by session id returns the chat to the queue" do
    {_token, ticket} = accepted_chat()
    session = repo().get_by!(ChatSession, ticket_id: ticket.id)
    department = repo().insert!(%Department{name: "Billing", slug: "billing", is_active: true})

    conn =
      agent(:post, "/support/agent/chat/#{session.id}/transfer", %{
        "department_id" => department.id
      })

    assert conn.status == 200, conn.resp_body
    saved = repo().get!(ChatSession, session.id)
    assert saved.agent_id == nil
    assert saved.status == "waiting"
    assert repo().get!(Ticket, ticket.id).department_id == department.id
  end

  test "no target, an unknown session, an ended chat or a non-agent is refused" do
    {_token, ticket} = accepted_chat()
    session = repo().get_by!(ChatSession, ticket_id: ticket.id)
    path = "/support/agent/chat/#{session.id}/transfer"

    assert agent(:post, path, %{"agent_id" => 2}, user: %{id: 7}).status == 403
    assert agent(:post, path, %{}).status == 422
    assert agent(:post, "/support/agent/chat/999999/transfer", %{"agent_id" => 2}).status == 404

    assert agent(:post, "/support/agent/chat/not-a-number/transfer", %{"agent_id" => 2}).status ==
             404

    assert repo().get!(ChatSession, session.id).agent_id == 1

    assert agent(:post, "/support/agent/chat/#{session.id}/end", %{}).status == 200
    conn = agent(:post, path, %{"agent_id" => 2})
    assert conn.status == 422
    assert Jason.decode!(conn.resp_body) == %{"message" => "Chat is already ended."}
  end

  test "the ticket-id route still transfers the chat" do
    {_token, ticket} = accepted_chat()

    conn = agent(:post, "/support/agent/chat/sessions/#{ticket.id}/transfer", %{"agent_id" => 2})
    assert conn.status == 200, conn.resp_body
    assert repo().get_by!(ChatSession, ticket_id: ticket.id).agent_id == 2
  end

  defp chat_with_distinct_ids(decoy) do
    repo().insert!(%ChatSession{ticket_id: decoy.id, status: "ended"})
    {_token, ticket} = accepted_chat()
    session = repo().get_by!(ChatSession, ticket_id: ticket.id)

    # Each pass moves the session sequence one further than the ticket
    # sequence, so the ids can match on at most one pass.
    if session.id == ticket.id, do: chat_with_distinct_ids(decoy), else: {ticket, session}
  end

  defp accepted_chat do
    {token, ticket} = start_chat()
    conn = agent(:post, "/support/agent/chat/sessions/#{ticket.id}/accept")
    assert conn.status == 200, conn.resp_body
    {token, ticket}
  end

  defp start_chat do
    params =
      %{"name" => "Visitor", "message" => "Hello"}
      |> Map.merge(GuestAccessHelpers.proof(@email, "chat"))

    conn = widget(:post, "/support/widget/chat/start", params)
    assert conn.status == 201, conn.resp_body
    token = Jason.decode!(conn.resp_body)["id"]
    {token, repo().one!(from(t in Ticket, order_by: [desc: t.id], limit: 1))}
  end

  defp widget(method, path, body) do
    conn(method, @host <> path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_req_header("origin", @shop)
    |> Map.put(:remote_ip, {10, 3, :rand.uniform(250), :rand.uniform(250)})
    |> init_test_session(%{})
    |> WidgetEmbedRouter.call(WidgetEmbedRouter.init([]))
  end

  defp agent(method, path, body \\ nil, opts \\ []) do
    user = Keyword.get(opts, :user, %{id: 1, is_admin: true, is_agent: true})

    conn =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end
      |> init_test_session(%{})
      |> assign(:current_user, user)

    conn =
      if opts[:inertia] do
        conn
        |> put_req_header("x-inertia", "true")
        |> put_req_header("x-inertia-version", inertia_version())
      else
        put_req_header(conn, "accept", "application/json")
      end

    Router.call(conn, Router.init([]))
  end
end
