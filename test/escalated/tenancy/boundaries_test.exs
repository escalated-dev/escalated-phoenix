defmodule Escalated.Tenancy.BoundariesTest do
  use Escalated.DataCase, async: false

  alias Escalated.{Broadcasting, Plugins, Tenancy, TestRepo, Webhooks}
  alias Escalated.Channels.{ChatChannel, TenantChannel, TicketChannel}
  alias Escalated.Controllers.Admin.{PluginController, UserController}
  alias Escalated.Schemas.{Permission, Role, RolePermission, Tag, Ticket, TicketTag, Webhook}
  alias Escalated.Services.{EmailChannelService, WebhookDispatcher}
  alias Escalated.Services.Newsletter.RateLimit

  @pubsub Escalated.Test.TenancyBoundaryPubSub
  @agent %{id: 42, is_agent: true}
  @keys ~w(tenancy_enabled tenant_resolver agent_check admin_check broadcasting_enabled pubsub_server
    webhook_sync webhook_http_client plugins hooks filters guest_access_secret)a

  defmodule Resolver do
    def member?(%{id: id}, tenant), do: Process.get({:member, tenant, id}, true)
    def member?(_, _), do: false
    def reference?(_, _, _), do: true
    def scope_users(query, _tenant), do: query
  end

  defmodule PlatformPlugin do
    def slug, do: raise("platform plugin must not execute inside a merchant")
  end

  setup do
    previous = Map.new(@keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, Resolver)
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
    Application.delete_env(:escalated, :admin_check)
    Application.put_env(:escalated, :hooks, %{})
    Application.put_env(:escalated, :filters, %{})
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    Application.put_env(:escalated, :broadcasting_enabled, true)
    Application.put_env(:escalated, :pubsub_server, @pubsub)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  defp ticket!(tenant) do
    TestRepo.insert!(%Ticket{
      tenant_id: tenant,
      subject: "Tenant ticket",
      description: "Private correspondence",
      requester_id: @agent.id,
      channel: "chat",
      guest_token: "obsolete-guest-token"
    })
  end

  defp topic(tenant, suffix),
    do: Tenancy.run(tenant, fn -> Tenancy.topic("escalated:" <> suffix) end)

  defp socket(tenant, user \\ @agent),
    do: %Phoenix.Socket{assigns: %{escalated_tenant_id: tenant, current_user: user}}

  test "socket tenant membership, namespace and ticket ownership are all required" do
    own = ticket!("merchant-a")
    foreign = ticket!("merchant-b")
    own_topic = topic("merchant-a", "ticket:#{own.id}")

    assert {:ok, _} = TicketChannel.join(own_topic, %{}, socket("merchant-a"))
    assert {:error, _} = TicketChannel.join(own_topic, %{}, socket("merchant-b"))
    assert {:error, _} = TicketChannel.join(own_topic, %{}, socket(nil))

    assert {:error, _} =
             TicketChannel.join("escalated:ticket:#{own.id}", %{}, socket("merchant-a"))

    assert {:error, _} =
             TicketChannel.join(
               topic("merchant-a", "ticket:#{foreign.id}"),
               %{},
               socket("merchant-a")
             )

    Process.put({:member, "merchant-a", @agent.id}, false)
    assert {:error, _} = TicketChannel.join(own_topic, %{}, socket("merchant-a"))
    assert_raise Tenancy.Error, fn -> Tenancy.current_id!() end
  end

  test "revoking membership closes existing ticket and chat subscriptions before delivery" do
    assert {:ok, ticket_socket} =
             TicketChannel.join(topic("merchant-a", "tickets"), %{}, socket("merchant-a"))

    assert {:ok, chat_socket} =
             ChatChannel.join(topic("merchant-a", "chat:queue"), %{}, socket("merchant-a"))

    Process.put({:member, "merchant-a", @agent.id}, false)
    message = %{event: "ticket:created", payload: %{subject: "Must not escape"}}
    assert {:stop, :normal, ^ticket_socket} = TicketChannel.handle_info(message, ticket_socket)

    assert {:stop, :normal, ^chat_socket} =
             ChatChannel.handle_in("typing", %{"typing" => true}, chat_socket)

    assert {:stop, :normal, ^chat_socket} =
             ChatChannel.handle_out("chat:typing", %{}, chat_socket)
  end

  test "tenant dispatcher routes chat and ticket topics and refuses guest sockets" do
    ticket = ticket!("merchant-a")

    assert {:ok, %{assigns: %{escalated_channel: ChatChannel}}} =
             TenantChannel.join(
               topic("merchant-a", "chat:#{ticket.id}"),
               %{},
               socket("merchant-a")
             )

    assert {:ok, %{assigns: %{escalated_channel: TicketChannel}}} =
             TenantChannel.join(topic("merchant-a", "tickets"), %{}, socket("merchant-a"))

    assert {:error, _} =
             TenantChannel.join(
               topic("merchant-a", "chat:#{ticket.id}"),
               %{"guest_token" => ticket.guest_token},
               socket("merchant-a", nil)
             )
  end

  test "broadcasts remain in their tenant namespace and reject foreign records before publishing" do
    own = ticket!("merchant-a")
    foreign = ticket!("merchant-b")
    Phoenix.PubSub.subscribe(@pubsub, topic("merchant-b", "tickets"))
    Phoenix.PubSub.subscribe(@pubsub, "escalated:tickets")

    Tenancy.run("merchant-a", fn -> Broadcasting.ticket_created(own) end)
    refute_receive %{event: "ticket:created"}

    Phoenix.PubSub.subscribe(@pubsub, topic("merchant-a", "tickets"))
    Tenancy.run("merchant-a", fn -> Broadcasting.ticket_created(own) end)
    assert_receive %{event: "ticket:created", payload: %{ticket_id: id}}
    assert id == own.id

    assert_raise Tenancy.Error, fn ->
      Tenancy.run("merchant-a", fn -> Broadcasting.ticket_created(foreign) end)
    end

    assert_raise ArgumentError, fn ->
      Tenancy.run("merchant-a", fn ->
        Broadcasting.broadcast_ticket_event("ticket:created", %{ticket_id: foreign.id})
      end)
    end

    refute_receive %{event: "ticket:created"}
  end

  test "raw repo parameters are normalized and rejected records cause no prior side effects" do
    own =
      TestRepo.insert!(%Webhook{
        tenant_id: "merchant-a",
        url: "https://a.test",
        events: ["ticket.created"]
      })

    foreign =
      TestRepo.insert!(%Webhook{
        tenant_id: "merchant-b",
        url: "https://b.test",
        events: ["ticket.created"]
      })

    alias Escalated.Schemas.EmailChannel

    default =
      TestRepo.insert!(%EmailChannel{
        tenant_id: "merchant-a",
        email_address: "a@example.com",
        is_default: true
      })

    other =
      TestRepo.insert!(%EmailChannel{tenant_id: "merchant-b", email_address: "b@example.com"})

    Tenancy.run("merchant-a", fn ->
      assert Enum.map(Webhooks.list(TestRepo), & &1.id) == [own.id]
      assert Webhooks.get(TestRepo, foreign.id) == nil
      assert_raise Tenancy.Error, fn -> Webhooks.delete(TestRepo, foreign) end
      assert_raise Tenancy.Error, fn -> EmailChannelService.set_default(TestRepo, other) end
    end)

    assert TestRepo.get!(EmailChannel, default.id).is_default
    assert TestRepo.get!(Webhook, foreign.id)
  end

  test "webhook worker captures the tenant and sends only that tenant's subscriptions" do
    parent = self()
    Application.put_env(:escalated, :webhook_sync, false)

    Application.put_env(:escalated, :webhook_http_client, fn url, _, _ ->
      send(parent, {:sent, url, Tenancy.current_id!(), self()})
      {:ok, %{status: 200, body: "ok"}}
    end)

    for tenant <- ["merchant-a", "merchant-b"] do
      TestRepo.insert!(%Webhook{
        tenant_id: tenant,
        url: "https://#{tenant}.test",
        events: ["ticket.created"]
      })
    end

    Tenancy.run("merchant-a", fn -> WebhookDispatcher.dispatch("ticket.created", %{}) end)
    assert_receive {:sent, "https://merchant-a.test", "merchant-a", pid}, 2_000
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 2_000
    refute_receive {:sent, _, _, _}
    assert_raise Tenancy.Error, fn -> Tenancy.current_id!() end
  end

  test "implicit many-to-many inserts stamp tenant identity on both pivot schemas" do
    ticket = ticket!("merchant-a")
    tag = TestRepo.insert!(%Tag{tenant_id: "merchant-a", name: "Parcel"})
    role = TestRepo.insert!(%Role{tenant_id: "merchant-a", name: "Support", slug: "support"})

    permission =
      TestRepo.insert!(%Permission{
        tenant_id: "merchant-a",
        name: "View tickets",
        slug: "tickets.view"
      })

    Tenancy.run("merchant-a", fn ->
      repo = Escalated.repo()

      ticket
      |> repo.preload(:tags)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:tags, [tag])
      |> repo.update!()

      role
      |> repo.preload(:permissions)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:permissions, [permission])
      |> repo.update!()
    end)

    assert [%TicketTag{tenant_id: "merchant-a"}] = TestRepo.all(TicketTag)
    assert [%RolePermission{tenant_id: "merchant-a"}] = TestRepo.all(RolePermission)
  end

  test "merchant administrators cannot enumerate host users or execute platform plugins" do
    Application.put_env(:escalated, :plugins, [PlatformPlugin])

    Tenancy.run("merchant-a", fn ->
      assert Plugins.registered_modules() == []
      assert Plugins.activate("platform") == {:error, :tenant_mode_unsupported}
      assert Plugins.deactivate("platform") == {:error, :tenant_mode_unsupported}
      assert Plugins.delete("platform") == {:error, :tenant_mode_unsupported}
      assert Plugins.all() == []

      assert UserController.index(Plug.Test.conn(:get, "/users"), %{}).status == 403

      assert UserController.update_role(Plug.Test.conn(:patch, "/users/1"), %{
               "user_id" => "1",
               "role" => "admin",
               "value" => true
             }).status == 403

      assert PluginController.index(Plug.Test.conn(:get, "/plugins"), %{}).status == 403
    end)
  end

  test "newsletter limits and reset operate on the current tenant only" do
    Tenancy.run("merchant-a", fn ->
      RateLimit.reset()
      RateLimit.increment(3)
    end)

    Tenancy.run("merchant-b", fn ->
      RateLimit.reset()
      RateLimit.increment(7)
    end)

    assert Tenancy.run("merchant-a", fn -> RateLimit.sent_this_minute() end) == 3
    assert Tenancy.run("merchant-b", fn -> RateLimit.sent_this_minute() end) == 7
    Tenancy.run("merchant-a", fn -> RateLimit.reset() end)
    assert Tenancy.run("merchant-a", fn -> RateLimit.sent_this_minute() end) == 0
    assert Tenancy.run("merchant-b", fn -> RateLimit.sent_this_minute() end) == 7
  end

  test "customer ticket channels suppress internal notes and project only public event fields" do
    ticket = ticket!("merchant-a")
    topic = topic("merchant-a", "ticket:#{ticket.id}")

    socket = %Phoenix.Socket{
      assigns: %{escalated_tenant_id: "merchant-a", current_user: %{id: @agent.id}},
      topic: topic,
      joined: true,
      transport_pid: self(),
      serializer: Phoenix.Socket.V2.JSONSerializer
    }

    assert {:ok, socket} = TicketChannel.join(topic, %{}, socket)

    for message <- [
          %{
            event: "ticket:reply_added",
            payload: %{ticket_id: ticket.id, is_internal: true, body: "Private note"}
          },
          %{
            event: "ticket:custom_action_triggered",
            payload: %{ticket_id: ticket.id, metadata: %{secret: "Private"}}
          }
        ] do
      assert {:noreply, ^socket} = TicketChannel.handle_info(message, socket)
      refute_receive {:socket_push, _, _}
    end

    message = %{
      event: "ticket:reply_added",
      payload: %{
        ticket_id: ticket.id,
        reply_id: 123,
        is_internal: false,
        metadata: %{secret: "Never forwarded"}
      }
    }

    assert {:noreply, ^socket} = TicketChannel.handle_info(message, socket)
    assert_receive {:socket_push, :text, json}

    assert [_, _, ^topic, "ticket:reply_added", payload] =
             json |> IO.iodata_to_binary() |> Jason.decode!()

    assert payload == %{"ticket_id" => ticket.id, "reply_id" => 123}

    TestRepo.update!(Ecto.Changeset.change(ticket, requester_type: "contact"))
    assert {:stop, :normal, ^socket} = TicketChannel.handle_info(message, socket)
  end

  test "single-tenant guest chat grants are rechecked for revocation and expiry after joining" do
    alias Escalated.Schemas.GuestGrant
    alias Escalated.Services.GuestAccess
    Application.put_env(:escalated, :tenancy_enabled, false)
    Application.put_env(:escalated, :guest_access_secret, String.duplicate("secret-", 8))

    for invalidation <- [:revoke, :expire] do
      ticket =
        TestRepo.insert!(%Ticket{
          subject: "Guest chat",
          description: "Hello",
          channel: "chat",
          guest_email: "guest@example.com"
        })

      {:ok, grant} =
        TestRepo.transaction(fn -> GuestAccess.issue(ticket, "chat", ticket.guest_email) end)

      topic = "escalated:chat:#{ticket.id}"

      assert {:ok, joined} =
               ChatChannel.join(
                 topic,
                 %{"guest_access_token" => grant["guest_access_token"]},
                 socket(nil, nil)
               )

      assert {:noreply, ^joined} = ChatChannel.handle_in("noop", %{}, joined)

      case invalidation do
        :revoke ->
          GuestAccess.revoke(ticket)

        :expire ->
          row = TestRepo.get_by!(GuestGrant, ticket_id: ticket.id)

          TestRepo.update!(
            Ecto.Changeset.change(row, expires_at: DateTime.add(GuestAccess.now(), -1))
          )
      end

      assert {:stop, :normal, ^joined} =
               ChatChannel.handle_in("typing", %{"typing" => true}, joined)

      assert {:stop, :normal, ^joined} =
               ChatChannel.handle_info(
                 %{event: "chat:message", payload: %{body: "Private"}},
                 joined
               )

      assert {:stop, :normal, ^joined} = ChatChannel.handle_out("chat:typing", %{}, joined)
    end
  end
end
