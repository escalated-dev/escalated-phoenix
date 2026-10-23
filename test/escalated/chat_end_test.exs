defmodule Escalated.ChatEndTest do
  @moduledoc """
  Ending a live chat from the agent ticket page. The shared frontend posts `{}`
  to escalated-laravel's `escalated.admin.chat.end` with the ChatSession's id
  (the ticket page's `chat_session_id`); in Phoenix that name maps to
  `POST /agent/chat/:session/end`. The older ticket-id route
  `POST /agent/chat/sessions/:id/end` keeps working.
  """
  use Escalated.PageCase

  import Ecto.Query

  alias Escalated.Schemas.{ChatSession, Ticket}
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

  test "posting {} to the session-id route ends the chat named by the ticket page's chat_session_id" do
    # A decoy chat with extra sessions pushes session ids away from ticket ids,
    # so a route that read the ticket id would not find this chat.
    {_decoy_token, decoy} = start_chat()

    for _ <- 1..3 do
      repo().insert!(%ChatSession{ticket_id: decoy.id, status: "ended"})
    end

    {_token, ticket} = accepted_chat()
    session = repo().get_by!(ChatSession, ticket_id: ticket.id)
    refute session.id == ticket.id

    page = agent(:get, "/support/agent/tickets/#{ticket.reference}", nil, inertia: true)
    assert page.status == 200, page.resp_body
    chat_session_id = Jason.decode!(page.resp_body)["props"]["ticket"]["chat_session_id"]
    assert chat_session_id == session.id

    conn = agent(:post, "/support/agent/chat/#{chat_session_id}/end", %{})
    assert conn.status == 200, conn.resp_body
    assert Jason.decode!(conn.resp_body) == %{"message" => "Chat ended."}

    ended = repo().get!(ChatSession, session.id)
    assert ended.status == "ended"
    assert ended.ended_at

    # The decoy chat is untouched.
    assert repo().get_by!(ChatSession, ticket_id: decoy.id, status: "waiting")
  end

  test "an already-ended chat is a 422, an unknown session a 404, a non-agent a 403" do
    {_token, ticket} = accepted_chat()
    session = repo().get_by!(ChatSession, ticket_id: ticket.id)
    path = "/support/agent/chat/#{session.id}/end"

    assert agent(:post, path, %{}, user: %{id: 7}).status == 403
    assert repo().get!(ChatSession, session.id).status == "active"

    assert agent(:post, "/support/agent/chat/999999/end", %{}).status == 404
    assert agent(:post, "/support/agent/chat/not-a-number/end", %{}).status == 404

    assert agent(:post, path, %{}).status == 200
    conn = agent(:post, path, %{})
    assert conn.status == 422
    assert Jason.decode!(conn.resp_body) == %{"message" => "Chat is already ended."}
  end

  test "the ticket-id route still ends the chat with its old response" do
    {_token, ticket} = accepted_chat()

    conn = agent(:post, "/support/agent/chat/sessions/#{ticket.id}/end")
    assert conn.status == 200, conn.resp_body
    assert Jason.decode!(conn.resp_body) == %{"data" => %{"status" => "ended"}}
    assert repo().get_by!(ChatSession, ticket_id: ticket.id).status == "ended"
    assert repo().get!(Ticket, ticket.id)
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
