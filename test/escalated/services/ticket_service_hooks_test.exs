defmodule Escalated.Services.TicketServiceHooksTest do
  use Escalated.DataCase, async: false

  alias Escalated.Services.TicketService

  defmodule CapturePlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "capture"

    @impl true
    def handle_action(hook, args) do
      case Application.get_env(:escalated, :test_pid) do
        pid when is_pid(pid) -> send(pid, {:hook, hook, args})
        _ -> :ok
      end
    end
  end

  setup do
    saved = %{
      plugins: Application.get_env(:escalated, :plugins),
      filters: Application.get_env(:escalated, :filters),
      test_pid: Application.get_env(:escalated, :test_pid)
    }

    Application.put_env(:escalated, :plugins, [CapturePlugin])
    Application.put_env(:escalated, :test_pid, self())
    {:ok, _} = Escalated.Plugins.activate("capture")

    on_exit(fn -> Enum.each(saved, fn {key, value} -> restore(key, value) end) end)
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:escalated, key)
  defp restore(key, value), do: Application.put_env(:escalated, key, value)

  defp create_ticket! do
    attrs = %{subject: "Hi", description: "Body", status: "open", priority: "medium"}
    {:ok, ticket} = TicketService.create(attrs)
    ticket
  end

  test "create fires ticket_created with the inserted ticket" do
    ticket = create_ticket!()
    assert_received {:hook, "ticket_created", [%{id: id}]}
    assert id == ticket.id
  end

  test "resolving fires ticket_status_changed and ticket_resolved" do
    ticket = create_ticket!()
    {:ok, _} = TicketService.transition_status(ticket, "resolved")

    assert_received {:hook, "ticket_status_changed", [_ticket, "open", "resolved"]}
    assert_received {:hook, "ticket_resolved", [_]}
  end

  test "replying fires ticket_replied, an internal note fires internal_note_added" do
    ticket = create_ticket!()

    {:ok, _} = TicketService.reply(ticket, %{body: "Public", is_internal: false})
    assert_received {:hook, "ticket_replied", [_reply, _ticket]}

    {:ok, _} = TicketService.reply(ticket, %{body: "Private", is_internal: true})
    assert_received {:hook, "internal_note_added", [_reply, _ticket]}
  end

  test "list applies the ticket_list_data filter" do
    create_ticket!()
    marker = fn tickets, _filters -> Enum.map(tickets, &Map.put(&1, :subject, "FILTERED")) end
    Application.put_env(:escalated, :filters, %{"ticket_list_data" => [marker]})

    subjects = TicketService.list() |> Enum.map(& &1.subject) |> Enum.uniq()
    assert subjects == ["FILTERED"]
  end
end
