defmodule Escalated.Schemas.AuditLogTest do
  use ExUnit.Case, async: true
  alias Escalated.Schemas.AuditLog

  test "changeset validates required fields" do
    changeset = AuditLog.changeset(%AuditLog{}, %{})
    refute changeset.valid?
  end

  test "changeset accepts valid attributes" do
    changeset = AuditLog.changeset(%AuditLog{}, %{
      action: "ticket.updated",
      entity_type: "ticket",
      entity_id: 42,
      performer_type: "agent",
      performer_id: 5,
      old_values: %{"status" => "open"},
      new_values: %{"status" => "resolved"},
      ip_address: "127.0.0.1"
    })
    assert changeset.valid?
  end
end
