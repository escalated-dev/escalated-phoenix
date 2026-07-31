defmodule Escalated.Schemas.WebhookDeliveryTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.WebhookDelivery

  describe "changeset" do
    test "casts fields and requires webhook_id + event" do
      cs =
        WebhookDelivery.changeset(%WebhookDelivery{}, %{
          webhook_id: 5,
          event: "ticket.created",
          payload: %{"ticket" => %{"id" => 1}},
          response_code: 200,
          response_body: "ok",
          attempts: 1
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :webhook_id) == 5
      assert Ecto.Changeset.get_field(cs, :event) == "ticket.created"
    end

    test "invalid without webhook_id or event" do
      refute WebhookDelivery.changeset(%WebhookDelivery{}, %{event: "x"}).valid?
      refute WebhookDelivery.changeset(%WebhookDelivery{}, %{webhook_id: 1}).valid?
    end
  end

  describe "success?/1" do
    test "true for 2xx, false otherwise" do
      assert WebhookDelivery.success?(%WebhookDelivery{response_code: 200})
      assert WebhookDelivery.success?(%WebhookDelivery{response_code: 299})
      refute WebhookDelivery.success?(%WebhookDelivery{response_code: 300})
      refute WebhookDelivery.success?(%WebhookDelivery{response_code: 500})
      refute WebhookDelivery.success?(%WebhookDelivery{response_code: 0})
      refute WebhookDelivery.success?(%WebhookDelivery{response_code: nil})
    end
  end

  describe "to_json/1" do
    test "includes a computed success flag" do
      json =
        WebhookDelivery.to_json(%WebhookDelivery{
          id: 9,
          webhook_id: 5,
          event: "ticket.created",
          response_code: 204,
          attempts: 1
        })

      assert json.id == 9
      assert json.webhook_id == 5
      assert json.event == "ticket.created"
      assert json.success == true
    end
  end
end
