defmodule Escalated.Services.WebhookDispatcherTest do
  use Escalated.DataCase, async: false

  import Ecto.Query

  alias Escalated.Schemas.WebhookDelivery
  alias Escalated.Services.WebhookDispatcher
  alias Escalated.Webhooks

  defp repo, do: Escalated.repo()

  setup do
    # Deliver inline so rows land on the test's sandbox connection, and skip
    # retry backoff sleeps.
    Application.put_env(:escalated, :webhook_sync, true)

    on_exit(fn ->
      Application.delete_env(:escalated, :webhook_sync)
      Application.delete_env(:escalated, :webhook_http_client)
    end)

    :ok
  end

  # Stub HTTP client: records every request to the test process and returns
  # the given canned response.
  defp stub_client(response) do
    test_pid = self()

    Application.put_env(:escalated, :webhook_http_client, fn url, headers, body ->
      send(test_pid, {:webhook_request, url, headers, body})
      response
    end)
  end

  defp insert_webhook!(attrs \\ %{}) do
    defaults = %{url: "https://example.test/hook", events: ["ticket.created"], active: true}
    {:ok, webhook} = Webhooks.create(repo(), Map.merge(defaults, attrs))
    webhook
  end

  defp deliveries_for(webhook_id) do
    repo().all(from(d in WebhookDelivery, where: d.webhook_id == ^webhook_id, order_by: d.id))
  end

  defp header(headers, key) do
    Enum.find_value(headers, fn {k, v} -> if String.downcase(k) == key, do: v end)
  end

  test "dispatch delivers to a subscribed active webhook and records the delivery" do
    webhook = insert_webhook!()
    stub_client({:ok, %{status: 200, body: "thanks"}})

    WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

    assert_received {:webhook_request, "https://example.test/hook", headers, body}
    assert header(headers, "content-type") == "application/json"
    assert header(headers, "x-escalated-event") == "ticket.created"

    decoded = Jason.decode!(body)
    assert decoded["event"] == "ticket.created"
    assert decoded["payload"] == %{"ticket" => %{"id" => 1}}
    assert is_binary(decoded["timestamp"])

    [delivery] = deliveries_for(webhook.id)
    assert delivery.event == "ticket.created"
    assert delivery.response_code == 200
    assert delivery.response_body == "thanks"
    assert delivery.attempts == 1
    assert delivery.delivered_at
  end

  test "adds a lower-case hex HMAC-SHA256 signature only when a secret is set" do
    insert_webhook!(%{secret: "s3cr3t"})
    stub_client({:ok, %{status: 200, body: "ok"}})

    WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

    assert_received {:webhook_request, _url, headers, body}
    signature = header(headers, "x-escalated-signature")
    assert signature == WebhookDispatcher.sign(body, "s3cr3t")
    assert signature =~ ~r/^[0-9a-f]{64}$/
  end

  test "omits the signature header when no secret is set" do
    insert_webhook!(%{secret: nil})
    stub_client({:ok, %{status: 200, body: "ok"}})

    WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

    assert_received {:webhook_request, _url, headers, _body}
    assert header(headers, "x-escalated-signature") == nil
  end

  test "truncates the stored response body to 2000 chars" do
    webhook = insert_webhook!()
    stub_client({:ok, %{status: 200, body: String.duplicate("x", 5000)}})

    WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

    [delivery] = deliveries_for(webhook.id)
    assert String.length(delivery.response_body) == 2000
  end

  test "retries up to 3 attempts on non-2xx, one delivery row per attempt" do
    webhook = insert_webhook!()
    stub_client({:ok, %{status: 500, body: "boom"}})

    WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

    deliveries = deliveries_for(webhook.id)
    assert length(deliveries) == 3
    assert Enum.map(deliveries, & &1.attempts) == [1, 2, 3]
    assert Enum.all?(deliveries, &(&1.response_code == 500))
  end

  test "records response_code 0 and retries on transport error" do
    webhook = insert_webhook!()
    stub_client({:error, :econnrefused})

    WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

    deliveries = deliveries_for(webhook.id)
    assert length(deliveries) == 3
    assert Enum.all?(deliveries, &(&1.response_code == 0))
  end

  test "does not deliver to inactive or non-subscribed webhooks" do
    _inactive = insert_webhook!(%{active: false})
    _other = insert_webhook!(%{events: ["ticket.closed"]})
    stub_client({:ok, %{status: 200, body: "ok"}})

    WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

    refute_received {:webhook_request, _, _, _}
    assert repo().aggregate(WebhookDelivery, :count) == 0
  end

  test "retry_delivery replays a recorded delivery as a fresh attempt" do
    webhook = insert_webhook!()

    delivery =
      repo().insert!(
        WebhookDelivery.changeset(%WebhookDelivery{}, %{
          webhook_id: webhook.id,
          event: "ticket.created",
          payload: %{"ticket" => %{"id" => 99}},
          response_code: 500,
          attempts: 3
        })
      )

    stub_client({:ok, %{status: 200, body: "ok"}})
    WebhookDispatcher.retry_delivery(delivery)

    assert_received {:webhook_request, _url, _headers, body}
    assert Jason.decode!(body)["payload"] == %{"ticket" => %{"id" => 99}}

    # Original row plus the fresh attempt.
    latest = repo().one(from(d in WebhookDelivery, order_by: [desc: d.id], limit: 1))
    assert latest.id != delivery.id
    assert latest.response_code == 200
    assert latest.attempts == 1
  end

  describe "outbound URL guard" do
    defp insert_raw_webhook!(url) do
      # Straight into the table, as a row saved before the guard existed would be.
      Escalated.TestRepo.insert!(%Escalated.Schemas.Webhook{
        url: url,
        events: ["ticket.created"],
        active: true
      })
    end

    for url <- [
          "http://169.254.169.254/latest/meta-data/",
          "http://127.0.0.1:4000/admin",
          "http://10.0.0.5/hook",
          "http://[::1]/hook",
          "http://[::ffff:192.168.1.1]/hook",
          "file:///etc/passwd",
          "gopher://example.test/"
        ] do
      test "refuses to send to #{url}, records why and does not retry" do
        webhook = insert_raw_webhook!(unquote(url))
        stub_client({:ok, %{status: 200, body: "secret internal data"}})

        WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

        refute_received {:webhook_request, _, _, _}
        assert [delivery] = deliveries_for(webhook.id)
        assert delivery.response_code == 0
        assert delivery.response_body =~ "public address"
        assert is_nil(delivery.delivered_at)
      end
    end

    test "re-checks the host on every send, so a host re-pointed at a private address is refused" do
      webhook = insert_webhook!(%{url: "https://rebind.test/hook"})
      stub_client({:ok, %{status: 200, body: "ok"}})

      Application.put_env(:escalated, :outbound_url_resolver, fn _ -> ["169.254.169.254"] end)

      on_exit(fn ->
        Application.put_env(:escalated, :outbound_url_resolver, fn host ->
          if String.ends_with?(host, ".test"), do: ["93.184.215.14"], else: []
        end)
      end)

      WebhookDispatcher.dispatch("ticket.created", %{ticket: %{id: 1}})

      refute_received {:webhook_request, _, _, _}
      assert [%{response_code: 0}] = deliveries_for(webhook.id)
    end

    test "the default client connects to the checked address under the original host name" do
      assert {"https://93.184.215.14/hook?x=1", headers, [ssl: ssl]} =
               WebhookDispatcher.pinned_request("https://hooks.test/hook?x=1", {93, 184, 215, 14})

      assert {"host", "hooks.test"} in headers
      assert ssl[:server_name_indication] == ~c"hooks.test"
      assert ssl[:verify] == :verify_peer

      assert {"http://93.184.215.14:8080/in", headers, []} =
               WebhookDispatcher.pinned_request("http://hooks.test:8080/in", {93, 184, 215, 14})

      assert {"host", "hooks.test:8080"} in headers

      assert {"http://[2606:4700::1111]/in", _, []} =
               WebhookDispatcher.pinned_request(
                 "http://hooks.test/in",
                 {0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}
               )

      # An IP literal is already pinned.
      assert {"https://93.184.215.14/in", [], []} =
               WebhookDispatcher.pinned_request("https://93.184.215.14/in", {93, 184, 215, 14})
    end
  end
end
