defmodule Escalated.Controllers.WorkflowLogsPageTest do
  @moduledoc """
  `Escalated/Admin/Workflows/Logs` against the props the shared page reads
  (escalated-laravel's `WorkflowController::logs`): `logs`, each with the
  workflow name, ticket reference, event, match, status, duration, the action
  count and the action details, and `workflows` for the filter.
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{Workflow, WorkflowLog}
  alias Escalated.Services.TicketService

  defp repo, do: Escalated.repo()

  defp workflow!(name) do
    %Workflow{}
    |> Workflow.changeset(%{
      name: name,
      trigger_event: "ticket.created",
      conditions: %{"all" => []},
      actions: [%{"type" => "change_priority", "value" => "high"}],
      is_active: false
    })
    |> repo().insert!()
  end

  setup do
    admin = host_user!(%{name: "Ada", is_admin: true, is_agent: true})
    first = workflow!("Route refunds")
    second = workflow!("Tag VIPs")
    {:ok, ticket} = TicketService.create(%{subject: "Refund", description: "x"})
    started = DateTime.utc_now() |> DateTime.truncate(:second)

    repo().insert!(
      WorkflowLog.changeset(%WorkflowLog{}, %{
        workflow_id: first.id,
        ticket_id: ticket.id,
        trigger_event: "ticket.created",
        conditions_matched: true,
        status: "success",
        actions_executed: [%{"type" => "change_priority", "status" => "ok"}],
        started_at: started,
        completed_at: DateTime.add(started, 2)
      })
    )

    repo().insert!(
      WorkflowLog.changeset(%WorkflowLog{}, %{
        workflow_id: second.id,
        ticket_id: ticket.id,
        trigger_event: "ticket.created",
        conditions_matched: false,
        status: "skipped",
        started_at: started
      })
    )

    %{admin: admin, first: first, second: second, ticket: ticket}
  end

  test "sends the logs and the workflows for the filter", ctx do
    props =
      visit(:get, "/support/admin/workflows/logs", ctx.admin)
      |> page!("Escalated/Admin/Workflows/Logs")

    assert_keys(props, ~w(logs workflows))
    assert length(props["logs"]) == 2

    log = Enum.find(props["logs"], &(&1["workflow_name"] == "Route refunds"))

    assert_keys(
      log,
      ~w(id workflow_id workflow_name ticket_reference event matched status duration_ms actions_executed action_details error created_at),
      "log"
    )

    assert log["ticket_reference"] == ctx.ticket.reference
    assert log["event"] == "ticket.created"
    assert log["matched"] == true
    assert log["actions_executed"] == 1
    assert log["duration_ms"] == 2000
    assert [detail] = log["action_details"]
    assert_keys(detail, ~w(action_type status), "action detail")
    assert detail["action_type"] == "change_priority"

    assert Enum.map(props["workflows"], & &1["name"]) == ["Route refunds", "Tag VIPs"]
    assert_keys(hd(props["workflows"]), ~w(id name), "workflow")
  end

  test "filters by workflow", ctx do
    props =
      visit(:get, "/support/admin/workflows/logs?workflow=#{ctx.second.id}", ctx.admin)
      |> page!("Escalated/Admin/Workflows/Logs")

    assert [%{"workflow_name" => "Tag VIPs", "matched" => false}] = props["logs"]
  end

  test "a workflow's logs link goes to the filtered page", ctx do
    conn = visit(:get, "/support/admin/workflows/#{ctx.first.id}/logs", ctx.admin)
    assert conn.status in [302, 303]
    assert location(conn) == "/support/admin/workflows/logs?workflow=#{ctx.first.id}"
  end
end
