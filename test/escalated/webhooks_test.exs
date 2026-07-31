defmodule Escalated.WebhooksTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.WebhookDelivery
  alias Escalated.Webhooks

  defp repo, do: Escalated.repo()

  defp insert_webhook!(attrs \\ %{}) do
    defaults = %{url: "https://example.test/hook", events: ["ticket.created"], active: true}
    {:ok, webhook} = Webhooks.create(repo(), Map.merge(defaults, attrs))
    webhook
  end

  describe "create/update/delete + get" do
    test "creates and fetches a webhook" do
      webhook = insert_webhook!(%{events: ["ticket.created", "reply.created"]})
      assert Webhooks.get(repo(), webhook.id).url == "https://example.test/hook"
    end

    test "rejects an empty events list" do
      assert {:error, changeset} = Webhooks.create(repo(), %{url: "u", events: []})
      refute changeset.valid?
    end

    test "updates a webhook" do
      webhook = insert_webhook!()
      {:ok, updated} = Webhooks.update(repo(), webhook, %{active: false})
      refute updated.active
    end

    test "deletes a webhook" do
      webhook = insert_webhook!()
      {:ok, _} = Webhooks.delete(repo(), webhook)
      assert Webhooks.get(repo(), webhook.id) == nil
    end
  end

  describe "list_active/1 and subscribed_to/2" do
    test "list_active excludes inactive webhooks" do
      active = insert_webhook!()
      _inactive = insert_webhook!(%{active: false})

      ids = Webhooks.list_active(repo()) |> Enum.map(& &1.id)
      assert active.id in ids
      assert length(ids) == 1
    end

    test "subscribed_to returns only active webhooks subscribed to the event" do
      subscribed = insert_webhook!(%{events: ["ticket.created"]})
      _other_event = insert_webhook!(%{events: ["ticket.closed"]})
      _inactive = insert_webhook!(%{events: ["ticket.created"], active: false})

      matched = Webhooks.subscribed_to(repo(), "ticket.created")
      assert Enum.map(matched, & &1.id) == [subscribed.id]
    end
  end

  describe "delivery helpers" do
    test "list_with_delivery_stats reports count + latest delivery" do
      webhook = insert_webhook!()

      repo().insert!(
        WebhookDelivery.changeset(%WebhookDelivery{}, %{
          webhook_id: webhook.id,
          event: "ticket.created",
          response_code: 200,
          attempts: 1
        })
      )

      [stats] = Webhooks.list_with_delivery_stats(repo())
      assert stats.id == webhook.id
      assert stats.delivery_count == 1
      assert stats.latest_delivery.response_code == 200
    end

    test "list_deliveries returns rows newest first" do
      webhook = insert_webhook!()

      for code <- [200, 500] do
        repo().insert!(
          WebhookDelivery.changeset(%WebhookDelivery{}, %{
            webhook_id: webhook.id,
            event: "ticket.created",
            response_code: code,
            attempts: 1
          })
        )
      end

      [first | _] = Webhooks.list_deliveries(repo(), webhook.id)
      assert first.response_code == 500
    end
  end
end
