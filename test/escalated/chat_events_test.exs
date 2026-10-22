defmodule Escalated.ChatEventsTest do
  @moduledoc """
  Live chat events (escalated-developer-context
  `decisions/2026-10-21-event-vocabulary.md`) reach outbound webhooks and
  workflows, through the widget and agent chat routes.

  `chat.transferred` is covered by `chat_transfer_test.exs`. A chat webhook
  payload never carries the visitor's chat token, the visitor's email or the
  message body.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{
    ChatSession,
    Department,
    Ticket,
    WebhookDelivery,
    Workflow,
    WorkflowLog
  }

  alias Escalated.Test.{GuestAccessHelpers, Router, WidgetEmbedRouter}
  alias Escalated.Webhooks

  @host "https://help.example.com"
  @shop "https://shop.example.com"
  @emitted ~w(chat.started chat.assigned chat.message chat.ended)
  @email "visitor@example.test"
  @secret_message "my order number is 4242"

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

  test "the webhook form and the workflow builder offer the chat events this package emits" do
    for event <- @emitted do
      assert event in Escalated.Events.emitted()
    end

    webhooks = agent(:get, "/support/admin/webhooks", nil, inertia: true) |> page()
    assert Enum.all?(@emitted, &(&1 in webhooks["props"]["available_events"]))
  end

  test "chat events reach webhooks without the token, the email or the message body" do
    subscribe(@emitted)
    department = repo().insert!(%Department{name: "Sales", slug: "sales", is_active: true})

    {token, ticket} = start_chat(%{"department_id" => department.id})
    session = repo().get_by!(ChatSession, ticket_id: ticket.id)

    started = only("chat.started")

    assert started["chat"] == %{
             "session_id" => session.id,
             "ticket_id" => ticket.id,
             "status" => "waiting",
             "agent_id" => nil,
             "department_id" => department.id
           }

    assert agent(:post, "/support/agent/chat/sessions/#{ticket.id}/accept").status == 200
    assigned = only("chat.assigned")
    assert assigned["chat"]["agent_id"] == 1
    assert assigned["chat"]["status"] == "active"

    assert widget(:post, "/support/widget/chat/#{token}/messages", %{"body" => @secret_message}).status ==
             201

    message = only("chat.message")
    assert message["chat"]["author_type"] == "visitor"
    assert is_integer(message["chat"]["reply_id"])

    assert widget(:post, "/support/widget/chat/#{token}/end").status == 200
    ended = only("chat.ended")
    assert ended["chat"]["status"] == "ended"
    assert ended["chat"]["ended_by"] == "customer"

    for raw <- sent_bodies() do
      refute raw =~ @email
      refute raw =~ token
      refute raw =~ @secret_message
    end

    assert repo().all(from(d in WebhookDelivery, order_by: d.id, select: d.event)) == @emitted
  end

  test "an agent's message and end are sent as chat.message and chat.ended" do
    subscribe(["chat.message", "chat.ended"])
    {_token, ticket} = start_chat()
    assert agent(:post, "/support/agent/chat/sessions/#{ticket.id}/accept").status == 200

    assert agent(:post, "/support/agent/chat/sessions/#{ticket.id}/message", %{
             "body" => "How can I help?"
           }).status ==
             201

    assert agent(:post, "/support/agent/chat/sessions/#{ticket.id}/end").status == 200

    assert only("chat.message")["chat"]["author_type"] == "agent"
    assert only("chat.ended")["chat"]["ended_by"] == "agent"
    refute Enum.any?(sent_bodies(), &(&1 =~ "How can I help?"))
  end

  test "a webhook subscribed to the legacy chat names receives the canonical events" do
    subscribe(["chat.session_started", "chat.session_ended"])
    {token, _ticket} = start_chat()
    assert widget(:post, "/support/widget/chat/#{token}/end").status == 200

    assert repo().all(from(d in WebhookDelivery, order_by: d.id, select: d.event)) ==
             ["chat.started", "chat.ended"]
  end

  test "chat events run workflows, including one saved under a legacy name" do
    workflows =
      for event <- @emitted ++ ["chat.session_started"], into: %{} do
        {event, workflow!(event)}
      end

    {token, ticket} = start_chat()
    agent(:post, "/support/agent/chat/sessions/#{ticket.id}/accept")
    widget(:post, "/support/widget/chat/#{token}/messages", %{"body" => "Hi"})
    widget(:post, "/support/widget/chat/#{token}/end")

    for {event, wf} <- workflows do
      assert repo().exists?(
               from(l in WorkflowLog,
                 where: l.workflow_id == ^wf.id and l.ticket_id == ^ticket.id
               )
             ),
             "#{event} workflow never ran"
    end
  end

  # Helpers

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

  defp start_chat(extra \\ %{}) do
    params =
      %{"name" => "Visitor", "message" => "Hello"}
      |> Map.merge(GuestAccessHelpers.proof(@email, "chat"))
      |> Map.merge(extra)

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
    |> Map.put(:remote_ip, {10, 2, :rand.uniform(250), :rand.uniform(250)})
    |> init_test_session(%{})
    |> WidgetEmbedRouter.call(WidgetEmbedRouter.init([]))
  end

  defp agent(method, path, body \\ nil, opts \\ []) do
    conn =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end
      |> init_test_session(%{})
      |> assign(:current_user, %{id: 1, is_admin: true, is_agent: true})

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

  defp page(conn) do
    assert conn.status == 200, "expected a rendered page, got #{conn.status}: #{conn.resp_body}"
    Jason.decode!(conn.resp_body)
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
