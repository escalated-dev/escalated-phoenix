defmodule Escalated.Tenancy.IsolationTest do
  use Escalated.DataCase, async: false
  import Ecto.Query
  import Ecto.Changeset
  import Plug.Conn
  import Plug.Test
  alias Escalated.{HostTestRepo, Tenancy, TestRepo}
  alias Escalated.Schemas.{Contact, EscalatedSetting, Reply, Tag, Ticket, TicketLink, TicketTag}
  alias Escalated.Tenancy.Repo
  alias Escalated.Test.{HostUser, TenantResolver}

  setup do
    keys = [
      :tenancy_enabled,
      :tenant_resolver,
      :user_schema,
      :user_repo,
      :admin_check,
      :agent_check,
      :api_token_validator,
      :api_profile_updater,
      :api_token_refresher,
      :api_logout,
      :api_registrar
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, TenantResolver)
    Application.put_env(:escalated, :user_schema, HostUser)
    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.delete_env(:escalated, :admin_check)
    Application.delete_env(:escalated, :agent_check)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(HostTestRepo)
    Ecto.Adapters.SQL.Sandbox.mode(HostTestRepo, {:shared, self()})

    on_exit(fn ->
      Tenancy.clear()
      Ecto.Adapters.SQL.Sandbox.checkin(HostTestRepo)

      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    a =
      HostTestRepo.insert!(%HostUser{
        name: "a",
        email: "a@example.com",
        is_agent: true,
        is_admin: true
      })

    b =
      HostTestRepo.insert!(%HostUser{
        name: "b",
        email: "b@example.com",
        is_agent: true,
        is_admin: true
      })

    ticket_a = Tenancy.run("a", fn -> ticket("Merchant A", a.id) end)
    ticket_b = Tenancy.run("b", fn -> ticket("Merchant B", b.id) end)

    for user <- [a, b] do
      Tenancy.run(user.name, fn ->
        Repo.insert!(
          Escalated.Schemas.AgentProfile.changeset(%Escalated.Schemas.AgentProfile{}, %{
            user_id: user.id,
            role: "admin",
            is_active: true
          })
        )
      end)
    end

    %{a: a, b: b, ticket_a: ticket_a, ticket_b: ticket_b}
  end

  test "missing, malformed and nested tenant contexts fail closed and restore" do
    assert_raise Tenancy.Error, fn -> Repo.all(Ticket) end

    for id <- [nil, "", " a", "a ", String.duplicate("a", 129), "a" <> <<0>>] do
      assert_raise Tenancy.Error, fn -> Tenancy.run(id, fn -> :unexpected end) end
    end

    Tenancy.run("a", fn ->
      assert_raise RuntimeError, fn -> Tenancy.run("b", fn -> raise "stop" end) end
      assert Tenancy.current_id!() == "a"
    end)

    assert_raise Tenancy.Error, &Tenancy.current_id!/0
  end

  test "every ordinary read and aggregate hides other tenants and the legacy namespace", ctx do
    TestRepo.insert!(Ticket.changeset(%Ticket{}, %{subject: "Legacy", description: "private"}))

    Tenancy.run("a", fn ->
      assert [%{id: id}] = Repo.all(Ticket)
      assert id == ctx.ticket_a.id
      assert Repo.get(Ticket, ctx.ticket_b.id) == nil
      assert Repo.get_by(Ticket, reference: ctx.ticket_b.reference) == nil
      assert Repo.aggregate(Ticket, :count) == 1
      assert Repo.one(from(t in Ticket, select: t.subject)) == "Merchant A"
      assert Repo.exists?(Ticket)
    end)
  end

  test "host identities are separately scoped and reference checks reject another merchant",
       ctx do
    Tenancy.run("a", fn ->
      assert [%{id: id}] = Escalated.user_repo().all(HostUser)
      assert id == ctx.a.id
      refute Escalated.user_repo().get(HostUser, ctx.b.id)
      assert_raise Tenancy.Error, fn -> ticket("forged", ctx.b.id) end

      assert_raise Tenancy.Error, fn ->
        Repo.insert!(Contact.changeset(%Contact{}, %{email: "x@example.com", user_id: ctx.b.id}))
      end
    end)
  end

  test "foreign loaded structs, forged ownership and moving a primary key cannot write", ctx do
    Tenancy.run("a", fn ->
      for foreign <- [ctx.ticket_b, %{ctx.ticket_b | tenant_id: "a"}] do
        assert_raise Tenancy.Error, fn -> Repo.update(change(foreign, subject: "stolen")) end
        assert_raise Tenancy.Error, fn -> Repo.delete(foreign) end
      end

      assert_raise Tenancy.Error, fn -> Repo.update(change(ctx.ticket_a, tenant_id: "b")) end
      assert_raise Tenancy.Error, fn -> Repo.update(change(ctx.ticket_a, id: ctx.ticket_b.id)) end
      assert_raise Tenancy.Error, fn -> Repo.insert(change(%Ticket{}, id: ctx.ticket_b.id)) end
    end)

    assert TestRepo.get!(Ticket, ctx.ticket_b.id).subject == "Merchant B"
  end

  test "foreign keys, flat ticket links and polymorphic subjects are checked before insert",
       ctx do
    Tenancy.run("a", fn ->
      assert Escalated.Tenancy.Writes.polymorphic_entry("ticket").schema == Ticket
      assert Escalated.Tenancy.Writes.polymorphic_entry("contact").schema == Contact

      assert_raise Tenancy.Error, fn ->
        Repo.insert!(Reply.changeset(%Reply{}, %{ticket_id: ctx.ticket_b.id, body: "leak"}))
      end

      assert_raise Tenancy.Error, fn ->
        Repo.insert!(
          change(%TicketLink{},
            parent_ticket_id: ctx.ticket_a.id,
            child_ticket_id: ctx.ticket_b.id,
            link_type: "related"
          )
        )
      end

      assert_raise Tenancy.Error, fn ->
        Repo.insert!(
          change(%Escalated.Schemas.TicketSubject{},
            ticket_id: ctx.ticket_a.id,
            subject_type: "shipment",
            subject_id: "b-parcel",
            role: "primary"
          )
        )
      end
    end)
  end

  test "bulk writes cannot cross tenants or alter ownership and foreign references", ctx do
    Tenancy.run("a", fn ->
      assert {1, _} = Repo.update_all(Ticket, set: [subject: "updated"])
      assert_raise Tenancy.Error, fn -> Repo.update_all(Ticket, set: [tenant_id: "b"]) end
      assert_raise Tenancy.Error, fn -> Repo.update_all(Ticket, set: [assigned_to: ctx.b.id]) end

      assert_raise Tenancy.Error, fn ->
        Repo.insert_all(TicketTag, [%{ticket_id: ctx.ticket_b.id, tag_id: 1}])
      end

      assert {1, _} = Repo.delete_all(Ticket)
    end)

    assert TestRepo.get!(Ticket, ctx.ticket_b.id).subject == "Merchant B"
  end

  test "joins and many-to-many preloads scope the pivot and target", ctx do
    tag_a = Tenancy.run("a", fn -> Repo.insert!(Tag.changeset(%Tag{}, %{name: "a"})) end)
    tag_b = Tenancy.run("b", fn -> Repo.insert!(Tag.changeset(%Tag{}, %{name: "b"})) end)
    # Simulate imported/corrupt rows. Reads must not trust the pivot's FK alone.
    TestRepo.insert_all(TicketTag, [
      %{tenant_id: "a", ticket_id: ctx.ticket_a.id, tag_id: tag_a.id},
      %{tenant_id: "a", ticket_id: ctx.ticket_a.id, tag_id: tag_b.id},
      %{tenant_id: "b", ticket_id: ctx.ticket_b.id, tag_id: tag_a.id}
    ])

    Tenancy.run("a", fn ->
      assert [%{id: id}] = Repo.preload(ctx.ticket_a, :tags).tags
      assert id == tag_a.id
      assert [%{id: ^id}] = Repo.preload(%{ctx.ticket_a | tags: [tag_b]}, :tags).tags

      rows =
        Repo.all(
          from(t in Ticket,
            join: p in TicketTag,
            on: p.ticket_id == t.id,
            join: tag in Tag,
            on: tag.id == p.tag_id,
            select: tag.name
          )
        )

      assert rows == ["a"]
      assert_raise Tenancy.Error, fn -> Repo.preload(ctx.ticket_b, :tags) end
    end)
  end

  test "association writes stamp typed pivots and reject foreign put_assoc", ctx do
    tag_a = Tenancy.run("a", fn -> Repo.insert!(Tag.changeset(%Tag{}, %{name: "a"})) end)
    tag_b = Tenancy.run("b", fn -> Repo.insert!(Tag.changeset(%Tag{}, %{name: "b"})) end)

    Tenancy.run("a", fn ->
      own = Repo.preload(ctx.ticket_a, :tags)
      assert {:ok, _} = own |> change() |> put_assoc(:tags, [tag_a]) |> Repo.update()
      assert [%{tenant_id: "a"}] = Repo.all(TicketTag)

      assert_raise Tenancy.Error, fn ->
        own |> change() |> put_assoc(:tags, [tag_b]) |> Repo.update()
      end
    end)
  end

  test "ordinary preloads, nested preloads and query preloads are scoped", ctx do
    own =
      Tenancy.run("a", fn ->
        Repo.insert!(Reply.changeset(%Reply{}, %{ticket_id: ctx.ticket_a.id, body: "ours"}))
      end)

    TestRepo.insert!(
      Reply.changeset(%Reply{tenant_id: "b"}, %{ticket_id: ctx.ticket_a.id, body: "not ours"})
    )

    Tenancy.run("a", fn ->
      assert [%{replies: [%{id: id}]}] = Repo.all(from(t in Ticket, preload: [:replies]))
      assert id == own.id
      assert [%{ticket: %{tenant_id: "a"}}] = Repo.preload([own], ticket: [:replies])
    end)
  end

  test "tenant-local setting upserts use the same key without overwriting another merchant" do
    for tenant <- ["a", "b"] do
      Tenancy.run(tenant, fn ->
        assert {:ok, _} =
                 Escalated.Services.GeneralSettings.update(%{"show_powered_by" => tenant == "a"})

        assert {:ok, _} =
                 Escalated.Services.GeneralSettings.update(%{"show_powered_by" => tenant == "a"})
      end)
    end

    assert TestRepo.aggregate(EscalatedSetting, :count) == 2

    Tenancy.run("b", fn ->
      refute Escalated.Services.GeneralSettings.enabled?(:show_powered_by)
    end)
  end

  test "Multi merge and callback transactions receive the scoped repo" do
    Tenancy.run("a", fn ->
      assert {:ok, %{tag: tag, observed: "a"}} =
               Ecto.Multi.new()
               |> Ecto.Multi.insert(:tag, Tag.changeset(%Tag{}, %{name: "multi"}))
               |> Ecto.Multi.merge(fn %{tag: tag} ->
                 Ecto.Multi.run(Ecto.Multi.new(), :observed, fn repo, _ ->
                   {:ok, repo.get!(Tag, tag.id).tenant_id}
                 end)
               end)
               |> Repo.transaction()

      assert tag.tenant_id == "a"
      assert {:ok, [^tag]} = Repo.transaction(fn repo -> repo.all(Tag) end)
    end)
  end

  test "unknown sources, disguised sources and unscoped subqueries fail closed" do
    Tenancy.run("a", fn ->
      assert_raise Tenancy.Error, fn -> Repo.all("users") end
      assert_raise Tenancy.Error, fn -> Repo.all({"users", Ticket}) end

      assert_raise Tenancy.Error, fn ->
        Repo.all(from(t in Ticket, where: t.id in subquery(from(x in Ticket, select: x.id))))
      end
    end)
  end

  test "membership is independent of admin role and is checked again after revocation", ctx do
    Tenancy.run("a", fn ->
      assert Escalated.Permissions.admin?(ctx.a)
      refute Escalated.Permissions.admin?(ctx.b)
      HostTestRepo.update!(change(ctx.a, name: "b"))
      refute Escalated.Permissions.agent?(ctx.a)
      refute Escalated.TicketAccess.requester?(ctx.ticket_a, ctx.a)
    end)
  end

  test "host-wide staff flags never grant a merchant seat without a tenant profile", ctx do
    Tenancy.run("a", fn ->
      Repo.delete_all(Escalated.Schemas.AgentProfile)
      refute Escalated.Permissions.admin?(ctx.a)
      refute Escalated.Permissions.agent?(ctx.a)
      assert Tenancy.member?(ctx.a)
    end)
  end

  test "shared frontend receives its tenant broadcast prefix", ctx do
    Tenancy.run("a", fn ->
      props = Escalated.Plugs.ShareInertiaData.escalated_props(ctx.a, Escalated.configuration())
      assert props.tenant_id == "a"
      assert props.broadcasting.driver == "phoenix"

      assert props.broadcasting.channel_prefix ==
               String.trim_trailing(Tenancy.topic("escalated:"), ":")
    end)
  end

  test "HTTP resolves only trusted tenant context and clears it after each response", ctx do
    denied =
      conn(:get, "/support/api/v1/tickets?tenant_id=a")
      |> assign(:current_user, ctx.a)
      |> init_test_session(%{})
      |> Escalated.Test.Router.call([])

    assert denied.status == 403

    denied =
      conn(:get, "/support/api/v1/tickets")
      |> assign(:trusted_tenant, "b")
      |> assign(:current_user, ctx.a)
      |> init_test_session(%{})
      |> Escalated.Test.Router.call([])

    assert denied.status == 403

    allowed =
      conn(:get, "/support/api/v1/tickets/#{ctx.ticket_b.reference}")
      |> assign(:trusted_tenant, "a")
      |> assign(:current_user, ctx.a)
      |> init_test_session(%{})
      |> Escalated.Test.Router.call([])

    assert allowed.status == 404
    assert_raise Tenancy.Error, &Tenancy.current_id!/0
  end

  test "background work captures and restores tenant context explicitly" do
    fun =
      Tenancy.run("a", fn ->
        Tenancy.capture(fn -> {Tenancy.current_id!(), Repo.aggregate(Ticket, :count)} end)
      end)

    assert {"a", 1} == Task.async(fun) |> Task.await()
    assert_raise Tenancy.Error, &Tenancy.current_id!/0
  end

  test "prefix overrides, association joins and SQL-expression ownership updates are refused",
       ctx do
    Tenancy.run("a", fn ->
      assert_raise Tenancy.Error, fn -> Repo.all(Ecto.Query.put_query_prefix(Ticket, "other")) end
      assert_raise Tenancy.Error, fn -> Repo.all(from(t in Ticket, prefix: "other")) end

      assert_raise Tenancy.Error, fn ->
        Repo.all(from(t in Ticket, join: r in Reply, on: r.ticket_id == t.id, prefix: "other"))
      end

      assert_raise Tenancy.Error, fn ->
        Repo.all(from(t in Ticket, join: tag in assoc(t, :tags)))
      end

      assert_raise Tenancy.Error, fn ->
        Repo.update_all(from(t in Ticket, update: [set: [tenant_id: "b"]]), [])
      end

      assert_raise Tenancy.Error, fn ->
        Repo.update(Ecto.put_meta(ctx.ticket_a, prefix: "other"))
      end
    end)
  end

  test "bearer profile and token callbacks cannot mutate a nonmember", ctx do
    parent = self()
    Application.put_env(:escalated, :api_token_validator, fn _ -> {:ok, ctx.b} end)

    Application.put_env(:escalated, :api_profile_updater, fn _, _ ->
      send(parent, :unsafe)
      {:ok, ctx.b}
    end)

    Application.put_env(:escalated, :api_token_refresher, fn _ ->
      send(parent, :unsafe)
      {:ok, ctx.b}
    end)

    Application.put_env(:escalated, :api_logout, fn _ -> send(parent, :unsafe) end)

    Application.put_env(:escalated, :api_registrar, fn _ ->
      send(parent, :unsafe)
      {:ok, ctx.b}
    end)

    Tenancy.run("a", fn ->
      assert Escalated.Api.HostAuth.validate("token") == :unauthorized
      assert Escalated.Api.HostAuth.update_profile("token", %{}) == :unauthorized
      assert Escalated.Api.HostAuth.refresh("token") == :unauthorized
      assert Escalated.Api.HostAuth.logout("token") == :ok
      assert Escalated.Api.HostAuth.register(%{}) == :not_configured
    end)

    refute_received :unsafe
  end

  test "legacy backfill preview is read-only and assignment is explicit and atomic" do
    legacy =
      TestRepo.insert!(Ticket.changeset(%Ticket{}, %{subject: "legacy", description: "private"}))

    report = Tenancy.Backfill.preview("new-merchant")
    assert report.issues == []
    assert report.counts["tickets"] == 1
    assert TestRepo.get!(Ticket, legacy.id).tenant_id == ""
    assert_raise ArgumentError, fn -> Tenancy.Backfill.apply("new-merchant") end
    assert {:ok, _} = Tenancy.Backfill.apply("new-merchant", writers_stopped: true)
    assert TestRepo.get!(Ticket, legacy.id).tenant_id == "new-merchant"

    assert {:error, {:invalid, %{issues: [_ | _]}}} =
             Tenancy.Backfill.apply("new-merchant", writers_stopped: true)
  end

  test "legacy backfill refuses host references without destination membership", ctx do
    legacy =
      TestRepo.insert!(
        Ticket.changeset(%Ticket{}, %{
          subject: "legacy",
          description: "private",
          requester_id: ctx.a.id,
          requester_type: to_string(HostUser)
        })
      )

    assert {:error, {:invalid, %{issues: [_ | _]}}} =
             Tenancy.Backfill.apply("new-merchant", writers_stopped: true)

    assert TestRepo.get!(Ticket, legacy.id).tenant_id == ""
  end

  defp ticket(subject, user_id) do
    Ticket.changeset(%Ticket{}, %{
      subject: subject,
      description: "private",
      requester_id: user_id,
      requester_type: Atom.to_string(HostUser)
    })
    |> Repo.insert!()
  end
end
