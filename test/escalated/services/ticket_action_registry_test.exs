defmodule Escalated.Services.TicketActionRegistryTest do
  use ExUnit.Case, async: false

  alias Escalated.Services.TicketActionRegistry

  setup do
    on_exit(fn -> Application.delete_env(:escalated, :custom_actions) end)
    :ok
  end

  test "for_ticket/2 serializes a config action with sensible defaults" do
    Application.put_env(:escalated, :custom_actions, [%{key: "sync-crm", label: "Sync CRM"}])

    [action] = TicketActionRegistry.for_ticket(%{id: 1, reference: "TK-1"}, %{id: 9})

    assert action.key == "sync-crm"
    assert action.label == "Sync CRM"
    assert action.variant == "secondary"
    assert action.confirmation == nil
    assert action.disabled == false
    assert action.metadata == %{}
  end

  test "for_ticket/2 omits invisible actions and marks disabled ones" do
    Application.put_env(:escalated, :custom_actions, [
      %{key: "hidden", label: "Hidden", visible: false},
      %{key: "locked", label: "Locked", enabled: false}
    ])

    actions = TicketActionRegistry.for_ticket(%{id: 1}, %{id: 1})

    assert length(actions) == 1
    assert hd(actions).key == "locked"
    assert hd(actions).disabled == true
  end

  test "for_ticket/2 resolves function fields with ticket and user" do
    Application.put_env(:escalated, :custom_actions, [
      %{
        key: "dyn",
        label: fn ticket, _user -> "Sync " <> ticket.reference end,
        visible: fn _ticket, user -> user.id == 9 end,
        metadata: fn _ticket, _user -> %{icon: "refresh-cw"} end
      }
    ])

    ticket = %{id: 1, reference: "TK-1"}

    assert [%{label: "Sync TK-1", metadata: %{icon: "refresh-cw"}}] =
             TicketActionRegistry.for_ticket(ticket, %{id: 9})

    assert [] == TicketActionRegistry.for_ticket(ticket, %{id: 1})
  end

  test "find/1 returns the action map or nil" do
    Application.put_env(:escalated, :custom_actions, [%{key: "a", label: "A"}])

    assert TicketActionRegistry.find("a")
    refute TicketActionRegistry.find("missing")
  end
end
