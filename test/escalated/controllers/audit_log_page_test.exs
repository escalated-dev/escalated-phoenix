defmodule Escalated.Controllers.AuditLogPageTest do
  @moduledoc """
  `Escalated/Admin/AuditLog/Index` against the props the shared page reads
  (escalated-laravel's `AuditLogController`).
  """
  use Escalated.PageCase

  alias Escalated.Schemas.AuditLog

  @component "Escalated/Admin/AuditLog/Index"

  defp repo, do: Escalated.repo()

  defp log!(attrs) do
    repo().insert!(struct(AuditLog, Map.merge(%{entity_type: "workflow", entity_id: 1}, attrs)))
  end

  setup do
    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})
    other = host_user!(%{name: "Bo"})

    log!(%{
      action: "workflow.created",
      performer_id: admin.id,
      new_values: %{"name" => "A"},
      ip_address: "10.0.0.1"
    })

    log!(%{
      action: "workflow.updated",
      performer_id: other.id,
      entity_type: "macro",
      old_values: %{"name" => "A"}
    })

    %{admin: admin, other: other}
  end

  test "sends a paginator of logs and the filter options", ctx do
    props = visit(:get, "/support/admin/audit-log", ctx.admin) |> page!(@component)

    assert_keys(props, ~w(logs filters users actions resourceTypes))
    rows = assert_paginator(props["logs"])
    assert length(rows) == 2

    created = Enum.find(rows, &(&1["action"] == "workflow.created"))

    assert_keys(
      created,
      ~w(id action auditable_type auditable_id user old_values new_values ip_address created_at),
      "log"
    )

    assert created["user"]["name"] == "Ada Admin"
    assert created["auditable_type"] == "workflow"
    assert props["actions"] == ["workflow.created", "workflow.updated"]
    assert props["resourceTypes"] == ["macro", "workflow"]
    assert Enum.map(props["users"], & &1["name"]) == ["Ada Admin", "Bo"]
  end

  test "filters by user, action, type and date", ctx do
    path = "/support/admin/audit-log?user_id=#{ctx.other.id}&auditable_type=macro"
    props = visit(:get, path, ctx.admin) |> page!(@component)
    assert [%{"action" => "workflow.updated"}] = props["logs"]["data"]

    assert props["filters"] == %{
             "user_id" => to_string(ctx.other.id),
             "auditable_type" => "macro"
           }

    today = Date.utc_today() |> Date.to_iso8601()

    props =
      visit(:get, "/support/admin/audit-log?date_to=#{today}&action=workflow.created", ctx.admin)
      |> page!(@component)

    assert [%{"action" => "workflow.created"}] = props["logs"]["data"]

    props =
      visit(:get, "/support/admin/audit-log?date_from=2999-01-01", ctx.admin) |> page!(@component)

    assert props["logs"]["data"] == []
  end
end
