defmodule Escalated.Controllers.WidgetSubmissionTest do
  use Escalated.DataCase, async: false

  alias Escalated.Controllers.{WidgetChatController, WidgetController}
  alias Escalated.Schemas.{ChatSession, Contact, Reply, Ticket, TicketActivity}
  alias Escalated.TestRepo

  setup do
    previous = Application.fetch_env(:escalated, :widget_settings)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :widget_settings, value)
        :error -> Application.delete_env(:escalated, :widget_settings)
      end
    end)

    :ok
  end

  test "disabled ticket submissions return once without creating data" do
    Application.put_env(:escalated, :widget_settings, %{enabled: false})

    conn = WidgetController.create_ticket(Plug.Test.conn(:post, "/widget/tickets"), params())

    assert conn.status == 403
    assert conn.halted
    assert Jason.decode!(conn.resp_body) == %{"error" => "Widget is disabled"}
    assert_empty_submission_tables()
  end

  test "disabled chat submissions cannot create a ticket, session or first message" do
    Application.put_env(:escalated, :widget_settings, %{enabled: false})

    conn = WidgetChatController.start(Plug.Test.conn(:post, "/widget/chat"), params())

    assert conn.status == 403
    assert conn.halted
    assert Jason.decode!(conn.resp_body) == %{"error" => "Widget is disabled"}
    assert_empty_submission_tables()
  end

  test "enabled ticket submissions still create a ticket" do
    Application.put_env(:escalated, :widget_settings, %{enabled: true})
    conn = WidgetController.create_ticket(Plug.Test.conn(:post, "/widget/tickets"), params())

    assert conn.status == 201
    assert TestRepo.aggregate(Ticket, :count) == 1
    assert Jason.decode!(conn.resp_body)["ticket"]["subject"] == "Parcel question"
  end

  test "enabled chat submissions still create a ticket and session" do
    Application.put_env(:escalated, :widget_settings, %{enabled: true})
    conn = WidgetChatController.start(Plug.Test.conn(:post, "/widget/chat"), params())

    assert conn.status == 201
    assert TestRepo.aggregate(Ticket, :count) == 1
    assert TestRepo.aggregate(ChatSession, :count) == 1
    assert Jason.decode!(conn.resp_body)["data"]["session_id"]
  end

  defp params do
    %{
      "name" => "Recipient",
      "email" => "recipient@example.test",
      "subject" => "Parcel question",
      "description" => "Where is my parcel?",
      "message" => "Where is my parcel?"
    }
  end

  defp assert_empty_submission_tables do
    for schema <- [Ticket, ChatSession, Contact, Reply, TicketActivity] do
      assert TestRepo.aggregate(schema, :count) == 0
    end
  end
end
