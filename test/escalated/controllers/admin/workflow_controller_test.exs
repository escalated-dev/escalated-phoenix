defmodule Escalated.Controllers.Admin.WorkflowControllerTest do
  @moduledoc """
  Exercises the admin Workflow CRUD surface that lets an admin author the
  event-driven workflows the engine now runs.
  """
  use Escalated.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias Escalated.Controllers.Admin.WorkflowController
  alias Escalated.Schemas.Workflow

  defp repo, do: Escalated.repo()

  defp conn! do
    conn(:post, "/")
    |> init_test_session(%{})
    |> Phoenix.Controller.fetch_flash()
  end

  describe "module interface" do
    test "exposes the CRUD actions mirrored from the automation/macro admin controllers" do
      assert function_exported?(WorkflowController, :index, 2)
      assert function_exported?(WorkflowController, :show, 2)
      assert function_exported?(WorkflowController, :create, 2)
      assert function_exported?(WorkflowController, :update, 2)
      assert function_exported?(WorkflowController, :delete, 2)
    end
  end

  describe "create/2" do
    test "persists a workflow, mapping the builder's `trigger` key to trigger_event" do
      params = %{
        "name" => "Refund router",
        "trigger" => "ticket.created",
        "conditions" => %{},
        "actions" => [%{"type" => "change_priority", "value" => "high"}]
      }

      conn = WorkflowController.create(conn!(), params)
      assert conn.status == 302

      wf = repo().get_by(Workflow, name: "Refund router")
      assert wf.trigger_event == "ticket.created"
      assert wf.actions == [%{"type" => "change_priority", "value" => "high"}]
      # auto-assigned position (max + 1) on the first row
      assert wf.position == 1
    end

    test "rejects an invalid workflow with a 422 and errors" do
      conn = WorkflowController.create(conn!(), %{"trigger" => "ticket.created"})

      assert conn.status == 422
      assert repo().all(Workflow) == []
    end
  end

  describe "update/2" do
    test "renames and re-triggers an existing workflow" do
      {:ok, wf} =
        %Workflow{}
        |> Workflow.changeset(%{name: "Old", trigger_event: "ticket.created", conditions: %{}})
        |> repo().insert()

      conn =
        WorkflowController.update(conn!(), %{
          "id" => to_string(wf.id),
          "name" => "New name",
          "trigger" => "reply.created",
          "conditions" => %{}
        })

      assert conn.status == 302

      reloaded = repo().get(Workflow, wf.id)
      assert reloaded.name == "New name"
      assert reloaded.trigger_event == "reply.created"
    end
  end

  describe "delete/2" do
    test "removes the workflow" do
      {:ok, wf} =
        %Workflow{}
        |> Workflow.changeset(%{name: "Doomed", trigger_event: "ticket.created"})
        |> repo().insert()

      conn = WorkflowController.delete(conn!(), %{"id" => to_string(wf.id)})
      assert conn.status == 302
      assert repo().get(Workflow, wf.id) == nil
    end
  end

  describe "show/2 (not found)" do
    test "returns 404 for a missing workflow" do
      conn = WorkflowController.show(conn!(), %{"id" => "9999999"})
      assert conn.status == 404
    end
  end
end
