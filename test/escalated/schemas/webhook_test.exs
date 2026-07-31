defmodule Escalated.Schemas.WebhookTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.Webhook

  describe "changeset" do
    test "casts allowed fields and validates required url + non-empty events" do
      cs =
        Webhook.changeset(%Webhook{}, %{
          url: "https://example.test/hook",
          events: ["ticket.created", "reply.created"],
          secret: "shh",
          active: true
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :url) == "https://example.test/hook"
      assert Ecto.Changeset.get_field(cs, :events) == ["ticket.created", "reply.created"]
      assert Ecto.Changeset.get_field(cs, :active) == true
    end

    test "rejects a missing url" do
      cs = Webhook.changeset(%Webhook{}, %{events: ["ticket.created"]})
      refute cs.valid?
      assert %{url: _} = errors_on(cs)
    end

    test "rejects an empty events list" do
      cs = Webhook.changeset(%Webhook{}, %{url: "https://example.test/hook", events: []})
      refute cs.valid?
      assert %{events: _} = errors_on(cs)
    end

    test "rejects when events omitted (defaults to empty)" do
      cs = Webhook.changeset(%Webhook{}, %{url: "https://example.test/hook"})
      refute cs.valid?
      assert %{events: _} = errors_on(cs)
    end
  end

  describe "subscribed_to?/2" do
    test "true only for a subscribed event name" do
      webhook = %Webhook{events: ["ticket.created", "reply.created"]}
      assert Webhook.subscribed_to?(webhook, "ticket.created")
      assert Webhook.subscribed_to?(webhook, "reply.created")
      refute Webhook.subscribed_to?(webhook, "ticket.closed")
    end

    test "false when events is nil" do
      refute Webhook.subscribed_to?(%Webhook{events: nil}, "ticket.created")
    end
  end

  describe "active/1 query" do
    test "filters to active rows" do
      ecto_str = inspect(Webhook.active())
      assert ecto_str =~ "active == true"
    end
  end

  describe "to_json/1" do
    test "shapes the row and never exposes the raw secret" do
      json =
        Webhook.to_json(%Webhook{
          id: 3,
          url: "https://example.test/hook",
          events: ["ticket.created"],
          secret: "topsecret",
          active: true
        })

      assert json.id == 3
      assert json.url == "https://example.test/hook"
      assert json.events == ["ticket.created"]
      assert json.active == true
      assert json.has_secret == true
      refute Map.has_key?(json, :secret)
    end

    test "has_secret is false when no secret set" do
      json = Webhook.to_json(%Webhook{id: 1, url: "u", events: [], secret: nil, active: true})
      assert json.has_secret == false
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
