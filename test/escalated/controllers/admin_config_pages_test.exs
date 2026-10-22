defmodule Escalated.Controllers.AdminConfigPagesTest do
  @moduledoc """
  The admin configuration pages -- SLA policies, escalation rules and
  webhooks -- against the props the shared Vue pages read and the routes their
  forms post to (escalated-laravel's `SlaPolicyController`,
  `EscalationRuleController` and `WebhookController`).
  """
  use Escalated.PageCase

  alias Escalated.Schemas.{EscalationRule, SlaPolicy, Ticket, Webhook, WebhookDelivery}

  defp repo, do: Escalated.repo()

  @hours %{"low" => 24, "medium" => 8, "high" => 4, "urgent" => 2, "critical" => 1}

  setup do
    %{admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})}
  end

  defp policy!(attrs \\ %{}) do
    %SlaPolicy{}
    |> SlaPolicy.changeset(
      Map.merge(
        %{name: "Standard", first_response_hours: @hours, resolution_hours: @hours},
        attrs
      )
    )
    |> repo().insert!()
  end

  describe "SLA policies" do
    test "Index lists policies with their ticket counts", %{admin: admin} do
      policy = policy!()

      repo().insert!(
        Ticket.changeset(%Ticket{}, %{subject: "S", description: "d", sla_policy_id: policy.id})
      )

      props =
        visit(:get, "/support/admin/sla-policies", admin)
        |> page!("Escalated/Admin/SlaPolicies/Index")

      assert [row] = props["policies"]

      assert_keys(
        row,
        ~w(id name description is_default is_active business_hours_only first_response_hours resolution_hours tickets_count),
        "policy"
      )

      assert row["tickets_count"] == 1
    end

    test "create and edit render the form with its options", %{admin: admin} do
      props =
        visit(:get, "/support/admin/sla-policies/create", admin)
        |> page!("Escalated/Admin/SlaPolicies/Form")

      assert_keys(props, ~w(priorities targeted departments ticketTypes))
      assert props["priorities"] == Ticket.priorities()

      policy = policy!()

      props =
        visit(:get, "/support/admin/sla-policies/#{policy.id}/edit", admin)
        |> page!("Escalated/Admin/SlaPolicies/Form")

      assert_keys(
        props["policy"],
        ~w(id name first_response_hours resolution_hours is_default is_active),
        "policy"
      )
    end

    test "store, update and destroy take the form's body", %{admin: admin} do
      body = %{
        "name" => "Gold",
        "description" => "Fast",
        "is_default" => false,
        "first_response_hours" => @hours,
        "resolution_hours" => @hours,
        "business_hours_only" => false,
        "is_active" => true
      }

      conn = visit(:post, "/support/admin/sla-policies", admin, body)
      assert conn.status in [302, 303]
      assert location(conn) == "/support/admin/sla-policies"
      policy = repo().get_by!(SlaPolicy, name: "Gold")
      assert policy.first_response_hours["high"] == 4

      conn =
        visit(:put, "/support/admin/sla-policies/#{policy.id}", admin, %{
          body
          | "name" => "Platinum"
        })

      assert conn.status in [302, 303]
      assert repo().get!(SlaPolicy, policy.id).name == "Platinum"

      assert visit(:delete, "/support/admin/sla-policies/#{policy.id}", admin).status in [
               302,
               303
             ]

      assert repo().get(SlaPolicy, policy.id) == nil
    end

    test "an invalid policy goes back with errors", %{admin: admin} do
      conn = visit(:post, "/support/admin/sla-policies", admin, %{"name" => ""})
      assert conn.status in [302, 303]
      assert repo().aggregate(SlaPolicy, :count) == 0
    end
  end

  describe "escalation rules" do
    defp rule!(attrs) do
      %EscalationRule{}
      |> EscalationRule.changeset(
        Map.merge(
          %{
            name: "Late",
            trigger_type: "time_based",
            conditions: [%{"field" => "hours_since_created", "value" => "24"}],
            actions: [%{"type" => "change_priority", "value" => "high"}]
          },
          attrs
        )
      )
      |> repo().insert!()
    end

    test "Index lists every rule, inactive ones too", %{admin: admin} do
      rule!(%{name: "On"})
      rule!(%{name: "Off", is_active: false})

      props =
        visit(:get, "/support/admin/escalation-rules", admin)
        |> page!("Escalated/Admin/EscalationRules/Index")

      assert Enum.map(props["rules"], & &1["name"]) |> Enum.sort() == ["Off", "On"]

      assert_keys(
        hd(props["rules"]),
        ~w(id name trigger_type is_active order conditions actions),
        "rule"
      )
    end

    test "create and edit render the form", %{admin: admin} do
      props =
        visit(:get, "/support/admin/escalation-rules/create", admin)
        |> page!("Escalated/Admin/EscalationRules/Form")

      assert Map.get(props, "rule") == nil

      rule = rule!(%{})

      props =
        visit(:get, "/support/admin/escalation-rules/#{rule.id}/edit", admin)
        |> page!("Escalated/Admin/EscalationRules/Form")

      assert props["rule"]["id"] == rule.id
    end
  end

  describe "webhooks" do
    defp webhook! do
      %Webhook{}
      |> Webhook.changeset(%{
        url: "https://hooks.example.test/in",
        events: ["ticket.created"],
        secret: "s3cret",
        active: true
      })
      |> repo().insert!()
    end

    test "Index sends each webhook with its recent deliveries", %{admin: admin} do
      webhook = webhook!()

      repo().insert!(%WebhookDelivery{
        webhook_id: webhook.id,
        event: "ticket.created",
        payload: %{},
        response_code: 200,
        attempts: 1
      })

      props =
        visit(:get, "/support/admin/webhooks", admin) |> page!("Escalated/Admin/Webhooks/Index")

      assert [row] = props["webhooks"]
      assert_keys(row, ~w(id url events active deliveries), "webhook")
      assert [delivery] = row["deliveries"]
      assert_keys(delivery, ~w(id event response_code created_at), "delivery")
      refute Jason.encode!(props) =~ "s3cret"
    end

    test "create and edit render the form with the events on offer", %{admin: admin} do
      props =
        visit(:get, "/support/admin/webhooks/create", admin)
        |> page!("Escalated/Admin/Webhooks/Form")

      assert "ticket.created" in props["availableEvents"]

      webhook = webhook!()

      props =
        visit(:get, "/support/admin/webhooks/#{webhook.id}/edit", admin)
        |> page!("Escalated/Admin/Webhooks/Form")

      assert_keys(props["webhook"], ~w(id url events active), "webhook")
      refute Jason.encode!(props) =~ "s3cret"
    end

    test "DeliveryLog sends a paginator of deliveries", %{admin: admin} do
      webhook = webhook!()

      repo().insert!(%WebhookDelivery{
        webhook_id: webhook.id,
        event: "ticket.created",
        payload: %{"a" => 1},
        response_code: 500,
        attempts: 3
      })

      props =
        visit(:get, "/support/admin/webhooks/#{webhook.id}/deliveries", admin)
        |> page!("Escalated/Admin/Webhooks/DeliveryLog")

      assert_keys(props["webhook"], ~w(id url), "webhook")
      [delivery] = assert_paginator(props["deliveries"])
      assert_keys(delivery, ~w(id event payload response_code attempts created_at), "delivery")
    end

    test "retry answers on Laravel's route", %{admin: admin} do
      webhook = webhook!()

      delivery =
        repo().insert!(%WebhookDelivery{
          webhook_id: webhook.id,
          event: "ticket.created",
          payload: %{},
          attempts: 1
        })

      test_pid = self()

      Application.put_env(:escalated, :webhook_sync, true)

      Application.put_env(:escalated, :webhook_http_client, fn url, _headers, _body ->
        send(test_pid, {:posted, url})
        {:ok, %{status: 200, body: "ok"}}
      end)

      on_exit(fn ->
        Application.delete_env(:escalated, :webhook_sync)
        Application.delete_env(:escalated, :webhook_http_client)
      end)

      conn = visit(:post, "/support/admin/webhooks/deliveries/#{delivery.id}/retry", admin, %{})
      assert conn.status in [302, 303]
      assert_received {:posted, "https://hooks.example.test/in"}
    end
  end
end
