defmodule Escalated.ChatTransferTest do
  @moduledoc """
  Live chat transfer (escalated-laravel `ChatController::transfer` and
  `ChatSessionService::transferChat`): an agent hands a chat to another agent
  and/or department through `POST /agent/chat/sessions/:id/transfer`, and
  `chat.transferred` reaches webhooks and workflows.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{
    ChatSession,
    Department,
    Reply,
    Ticket,
    WebhookDelivery,
    Workflow,
    WorkflowLog
  }

  alias Escalated.Test.{GuestAccessHelpers, Router, WidgetEmbedRouter}
  alias Escalated.Webhooks

  @host "https://help.example.com"
  @shop "https://shop.example.com"
  @email "visitor@example.test"

  defp repo, do: Escalated.repo()

  setup do
    GuestAccessHelpers.configure()
    test_pid = self()

    keys = [
      :widget_allowed_origins,
      :widget_settings,
      :rate_limit_backend,
      :webhook_sync,
      :webhook_http_client
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :widget_allowed_origins, [@shop])
    Application.delete_env(:escalated, :widget_settings)
    Application.delete_env(:escalated, :rate_limit_backend)
    Application.put_env(:escalated, :webhook_sync, true)

    Application.put_env(:escalated, :webhook_http_client, fn _url, _headers, body ->
      send(test_pid, {:webhook_request, body})
      {:ok, %{status: 200, body: "ok"}}
    end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "chat.transferred is emitted and offered by the webhook form and workflow builder" do
    assert "chat.transferred" in Escalated.Events.emitted()

    webhooks = agent(:get, "/support/admin/webhooks", nil, inertia: true)
    assert webhooks.status == 200
    assert "chat.transferred" in Jason.decode!(webhooks.resp_body)["props"]["available_events"]
  end

  test "transferring to another agent reassigns the chat and its ticket" do
    subscribe(["chat.transferred"])
    {token, ticket} = accepted_chat()

    conn = agent(:post, "/support/agent/chat/sessions/#{ticket.id}/transfer", %{"agent_id" => 2})
    assert conn.status == 200, conn.resp_body
    assert Jason.decode!(conn.resp_body)["message"] == "Chat transferred."

    session = repo().get_by!(ChatSession, ticket_id: ticket.id)
    assert session.agent_id == 2
    assert repo().get!(Ticket, ticket.id).assigned_to == 2

    chat = only("chat.transferred")["chat"]
    assert chat["from_agent_id"] == 1
    assert chat["to_agent_id"] == 2
    assert chat["to_department_id"] == nil
    assert chat["agent_id"] == 2
    assert chat["ticket_id"] == ticket.id
    assert chat["session_id"] == session.id

    for raw <- sent_bodies() do
      refute raw =~ @email
      refute raw =~ token
    end

    # An internal system note records the transfer; the visitor's transcript
    # does not show it.
    assert repo().exists?(
             from(r in Reply,
               where:
                 r.ticket_id == ^ticket.id and r.is_system == true and r.is_internal == true and
                   like(r.body, "Chat transferred%")
             )
           )

    transcript = widget(:get, "/support/widget/chat/#{token}/messages")
    assert transcript.status == 200
    refute transcript.resp_body =~ "transferred"
  end

  test "transferring to a department returns the chat to the queue" do
    subscribe(["chat.transferred"])
    {_token, ticket} = accepted_chat()
    department = repo().insert!(%Department{name: "Billing", slug: "billing", is_active: true})

    conn =
      agent(:post, "/support/agent/chat/sessions/#{ticket.id}/transfer", %{
        "department_id" => department.id
      })

    assert conn.status == 200, conn.resp_body

    session = repo().get_by!(ChatSession, ticket_id: ticket.id)
    assert session.agent_id == nil
    assert session.status == "waiting"
    saved = repo().get!(Ticket, ticket.id)
    assert saved.assigned_to == nil
    assert saved.department_id == department.id

    chat = only("chat.transferred")["chat"]
    assert chat["from_agent_id"] == 1
    assert chat["to_agent_id"] == nil
    assert chat["to_department_id"] == department.id
    assert chat["status"] == "waiting"
    assert chat["department_id"] == department.id
  end

  test "an agent and a department together move the chat to that agent in that department" do
    {_token, ticket} = accepted_chat()
    department = repo().insert!(%Department{name: "Billing", slug: "billing", is_active: true})

    conn =
      agent(:post, "/support/agent/chat/sessions/#{ticket.id}/transfer", %{
        "agent_id" => "2",
        "department_id" => to_string(department.id)
      })

    assert conn.status == 200, conn.resp_body
    assert repo().get_by!(ChatSession, ticket_id: ticket.id).agent_id == 2
    assert repo().get!(Ticket, ticket.id).department_id == department.id
  end

  test "the shared ChatActionBar body {type, id} is accepted" do
    {_token, ticket} = accepted_chat()

    conn =
      agent(:post, "/support/agent/chat/sessions/#{ticket.id}/transfer", %{
        "type" => "agent",
        "id" => 2
      })

    assert conn.status == 200, conn.resp_body
    assert repo().get_by!(ChatSession, ticket_id: ticket.id).agent_id == 2
  end

  test "a transfer without a target, to an unknown department, of an unknown or ended chat, or by a non-agent is refused" do
    subscribe(["chat.transferred"])
    {token, ticket} = accepted_chat()
    path = "/support/agent/chat/sessions/#{ticket.id}/transfer"

    assert agent(:post, path, %{}).status == 422
    assert agent(:post, path, %{"department_id" => 999_999}).status == 422
    assert agent(:post, path, %{"agent_id" => "nope"}).status == 422

    assert agent(:post, "/support/agent/chat/sessions/999999/transfer", %{"agent_id" => 2}).status ==
             404

    assert agent(:post, path, %{"agent_id" => 2}, user: %{id: 7}).status == 403

    assert widget(:post, "/support/widget/chat/#{token}/end").status == 200
    assert agent(:post, path, %{"agent_id" => 2}).status == 422

    assert repo().get_by!(ChatSession, ticket_id: ticket.id).agent_id == 1
    refute repo().exists?(from(d in WebhookDelivery, where: d.event == "chat.transferred"))
  end

  test "chat.transferred runs workflows" do
    wf = workflow!("chat.transferred")
    {_token, ticket} = accepted_chat()

    assert agent(:post, "/support/agent/chat/sessions/#{ticket.id}/transfer", %{"agent_id" => 2}).status ==
             200

    assert repo().exists?(
             from(l in WorkflowLog, where: l.workflow_id == ^wf.id and l.ticket_id == ^ticket.id)
           )
  end

  # Helpers

  defp accepted_chat do
    {token, ticket} = start_chat()
    conn = agent(:post, "/support/agent/chat/sessions/#{ticket.id}/accept")
    assert conn.status == 200, conn.resp_body
    {token, ticket}
  end

  defp subscribe(events) do
    {:ok, _} =
      Webhooks.create(repo(), %{url: "https://example.test/hook", events: events, active: true})
  end

  defp sent_bodies do
    collect = fn collect, acc ->
      receive do
        {:webhook_request, body} -> collect.(collect, [body | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    bodies = collect.(collect, [])
    Enum.each(bodies, &send(self(), {:webhook_request, &1}))
    bodies
  end

  defp only(event) do
    matching =
      sent_bodies()
      |> Enum.map(&Jason.decode!/1)
      |> Enum.filter(&(&1["event"] == event))

    assert [one] = matching, "#{event} sent #{length(matching)} time(s)"
    one["payload"]
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

  defp workflow!(trigger_event) do
    %Workflow{}
    |> Workflow.changeset(%{
      name: "on #{trigger_event} #{System.unique_integer([:positive])}",
      trigger_event: trigger_event,
      conditions: %{"all" => []},
      actions: [%{"type" => "add_follower", "value" => "77"}],
      is_active: true
    })
    |> repo().insert!()
  end

  defp widget(method, path, body \\ nil) do
    conn(method, @host <> path, if(is_nil(body), do: nil, else: Jason.encode!(body)))
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

  defp inertia_version do
    conn(:get, "/")
    |> init_test_session(%{})
    |> Inertia.Plug.call(Inertia.Plug.init([]))
    |> Map.fetch!(:private)
    |> Map.fetch!(:inertia_version)
    |> to_string()
  end
end
