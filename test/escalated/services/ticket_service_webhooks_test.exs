defmodule Escalated.Services.TicketServiceWebhooksTest do
  use Escalated.DataCase, async: false

  import Ecto.Query

  alias Escalated.Schemas.WebhookDelivery
  alias Escalated.Services.TicketService
  alias Escalated.Webhooks

  defp repo, do: Escalated.repo()

  setup do
    Application.put_env(:escalated, :webhook_sync, true)
    test_pid = self()

    Application.put_env(:escalated, :webhook_http_client, fn _url, _headers, body ->
      send(test_pid, {:webhook_request, Jason.decode!(body)})
      {:ok, %{status: 200, body: "ok"}}
    end)

    on_exit(fn ->
      Application.delete_env(:escalated, :webhook_sync)
      Application.delete_env(:escalated, :webhook_http_client)
    end)

    {:ok, _} =
      Webhooks.create(repo(), %{
        url: "https://example.test/hook",
        events: ["ticket.created", "reply.created", "note.created", "ticket.status_changed"],
        active: true
      })

    :ok
  end

  defp create_ticket! do
    {:ok, ticket} =
      TicketService.create(%{
        subject: "Hi",
        description: "Body",
        status: "open",
        priority: "medium"
      })

    ticket
  end

  test "creating a ticket dispatches ticket.created and records a delivery" do
    ticket = create_ticket!()

    assert_received {:webhook_request, %{"event" => "ticket.created", "payload" => payload}}
    assert payload["ticket"]["id"] == ticket.id
    assert payload["ticket"]["reference"] == ticket.reference
    assert payload["ticket"]["subject"] == "Hi"

    assert delivered?("ticket.created")
  end

  test "a public reply dispatches reply.created with a trimmed ticket + reply" do
    ticket = create_ticket!()

    {:ok, reply} =
      TicketService.reply(ticket, %{body: "Public", is_internal: false, author_id: 1})

    assert_received {:webhook_request, %{"event" => "reply.created", "payload" => payload}}
    assert payload["ticket"] == %{"id" => ticket.id, "reference" => ticket.reference}
    assert payload["reply"] == %{"id" => reply.id, "is_internal_note" => false}

    assert delivered?("reply.created")
  end

  test "an internal note dispatches note.created" do
    ticket = create_ticket!()

    {:ok, _reply} =
      TicketService.reply(ticket, %{body: "Private", is_internal: true, author_id: 1})

    assert_received {:webhook_request, %{"event" => "note.created", "payload" => payload}}
    assert payload["reply"]["is_internal_note"] == true
  end

  test "a status transition dispatches ticket.status_changed" do
    ticket = create_ticket!()
    {:ok, _} = TicketService.transition_status(ticket, "resolved")

    assert_received {:webhook_request, %{"event" => "ticket.status_changed"}}
  end

  defp delivered?(event) do
    repo().exists?(
      from(d in WebhookDelivery, where: d.event == ^event and d.response_code == 200)
    )
  end
end
