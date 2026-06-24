defmodule Escalated.Services.EscalationServiceTest do
  use Escalated.DataCase, async: false

  import Ecto.Query

  alias Escalated.Schemas.{EscalationRule, Ticket, TicketActivity}
  alias Escalated.Services.EscalationService

  defp repo, do: Escalated.repo()

  defp insert_ticket!(attrs) do
    {:ok, t} =
      %Ticket{}
      |> Ticket.changeset(Map.merge(%{subject: "Subject", description: "Body"}, attrs))
      |> repo().insert()

    t
  end

  defp insert_rule!(attrs) do
    {:ok, r} =
      %EscalationRule{}
      |> EscalationRule.changeset(attrs)
      |> repo().insert()

    r
  end

  describe "changeset/2" do
    test "casts allowed fields and requires name" do
      cs =
        EscalationRule.changeset(%EscalationRule{}, %{
          name: "high-prio",
          trigger_type: "cron",
          conditions: [%{"field" => "priority", "value" => "high"}],
          actions: [%{"type" => "escalate"}]
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :name) == "high-prio"
      assert length(Ecto.Changeset.get_field(cs, :actions)) == 1
    end

    test "rejects when name is missing" do
      cs = EscalationRule.changeset(%EscalationRule{}, %{conditions: [], actions: []})
      refute cs.valid?
    end
  end

  describe "active/1" do
    test "filters to active rules ordered by order then id" do
      ecto_str = EscalationRule |> EscalationRule.active() |> inspect()
      assert ecto_str =~ "is_active == true"
      assert ecto_str =~ "order_by"
    end
  end

  describe "to_json/1" do
    test "shapes the row for the admin frontend" do
      json =
        EscalationRule.to_json(%EscalationRule{
          id: 3,
          name: "rule",
          trigger_type: "cron",
          conditions: [],
          actions: [],
          order: 2,
          is_active: true
        })

      assert json.id == 3
      assert json.is_active == true
      assert json.order == 2
      assert is_list(json.actions)
    end
  end

  describe "evaluate_rules/1" do
    test "escalates matching open tickets and logs an activity" do
      match = insert_ticket!(%{status: "open", priority: "high"})
      skip = insert_ticket!(%{status: "open", priority: "low"})

      insert_rule!(%{
        name: "escalate-high",
        trigger_type: "cron",
        conditions: [%{"field" => "priority", "value" => "high"}],
        actions: [%{"type" => "escalate"}]
      })

      count = EscalationService.evaluate_rules(repo())

      assert count == 1
      assert repo().get!(Ticket, match.id).status == "escalated"
      assert repo().get!(Ticket, skip.id).status == "open"

      activities = repo().all(from(a in TicketActivity, where: a.ticket_id == ^match.id))
      assert Enum.any?(activities, &(&1.action == "escalated"))
    end

    test "change_priority action updates the ticket priority" do
      ticket = insert_ticket!(%{status: "open", priority: "low"})

      insert_rule!(%{
        name: "bump",
        trigger_type: "cron",
        conditions: [%{"field" => "status", "value" => "open"}],
        actions: [%{"type" => "change_priority", "value" => "urgent"}]
      })

      EscalationService.evaluate_rules(repo())
      assert repo().get!(Ticket, ticket.id).priority == "urgent"
    end

    test "ignores inactive rules and resolved tickets" do
      resolved = insert_ticket!(%{status: "resolved", priority: "high", resolved_at: now()})

      insert_rule!(%{
        name: "inactive",
        trigger_type: "cron",
        is_active: false,
        conditions: [%{"field" => "priority", "value" => "high"}],
        actions: [%{"type" => "escalate"}]
      })

      assert EscalationService.evaluate_rules(repo()) == 0
      assert repo().get!(Ticket, resolved.id).status == "resolved"
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
