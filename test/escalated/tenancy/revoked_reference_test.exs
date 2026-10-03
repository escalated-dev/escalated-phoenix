defmodule Escalated.Tenancy.RevokedReferenceTest do
  @moduledoc """
  A merchant removes a user's membership while rows still name that user
  (an assigned ticket, a requester, an agent seat). Writes that do not touch
  those references must keep working; writes that set a reference must still
  prove it belongs to the merchant.

  Also covers `insert_all` row values, which Ecto can turn into SQL of their
  own and which the scoped repo cannot inspect.
  """
  use Escalated.DataCase, async: false
  import Ecto.Query
  import Ecto.Changeset
  alias Escalated.{HostTestRepo, Tenancy, TestRepo}
  alias Escalated.Schemas.{AgentProfile, Reply, Tag, Ticket}
  alias Escalated.Services.{AssignmentService, SlaService, TicketService}
  alias Escalated.Tenancy.{Maintenance, Repo}
  alias Escalated.Test.{HostUser, TenantResolver}

  defmodule CatalogResolver do
    @moduledoc false
    defdelegate resolve(conn), to: Escalated.Test.TenantResolver
    defdelegate member?(user, tenant), to: Escalated.Test.TenantResolver
    defdelegate reference?(kind, id, tenant), to: Escalated.Test.TenantResolver
    defdelegate scope_users(query, tenant), to: Escalated.Test.TenantResolver
    def tenants, do: ["a", "b"]
  end

  setup do
    keys = [
      :tenancy_enabled,
      :tenant_resolver,
      :user_schema,
      :user_repo,
      :admin_check,
      :agent_check
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

    admin = HostTestRepo.insert!(%HostUser{name: "a", email: "admin@a.test"})
    agent = HostTestRepo.insert!(%HostUser{name: "a", email: "agent@a.test"})
    customer = HostTestRepo.insert!(%HostUser{name: "a", email: "cust@a.test"})
    b = HostTestRepo.insert!(%HostUser{name: "b", email: "b@b.test"})

    for {user, role} <- [{admin, "admin"}, {agent, "agent"}] do
      Tenancy.run("a", fn -> seat!(user, role) end)
    end

    Tenancy.run("b", fn -> seat!(b, "admin") end)

    ticket_a = Tenancy.run("a", fn -> ticket!("A ticket", customer) end)
    ticket_b = Tenancy.run("b", fn -> ticket!("B SECRET SUBJECT", b) end)
    TestRepo.insert!(Ticket.changeset(%Ticket{}, %{subject: "LEGACY SECRET", description: "x"}))

    %{
      admin: admin,
      agent: agent,
      customer: customer,
      b: b,
      ticket_a: ticket_a,
      ticket_b: ticket_b
    }
  end

  defp seat!(user, role) do
    %AgentProfile{}
    |> AgentProfile.changeset(%{user_id: user.id, role: role, is_active: true})
    |> Repo.insert!()
  end

  defp ticket!(subject, requester) do
    %Ticket{}
    |> Ticket.changeset(%{
      subject: subject,
      description: "d",
      requester_id: requester.id,
      requester_type: Atom.to_string(HostUser)
    })
    |> Repo.insert!()
  end

  # The test resolver treats a user as a member of the tenant named in `name`.
  defp revoke(user), do: HostTestRepo.update!(change(user, name: "gone"))

  describe "after a membership is revoked" do
    test "a ticket assigned to that agent can still change status", ctx do
      Tenancy.run("a", fn ->
        {:ok, assigned} =
          AssignmentService.assign(ctx.ticket_a, ctx.agent.id, actor_id: ctx.admin.id)

        revoke(ctx.agent)

        assert {:ok, resolved} =
                 TicketService.transition_status(assigned, "resolved", actor_id: ctx.admin.id)

        assert resolved.status == "resolved"
        assert resolved.assigned_to == ctx.agent.id
      end)
    end

    test "an agent can reply on a ticket whose requester left", ctx do
      Tenancy.run("a", fn ->
        revoke(ctx.customer)

        assert {:ok, %Reply{}} =
                 TicketService.reply(ctx.ticket_a, %{body: "hello", author_id: ctx.admin.id})

        assert Repo.aggregate(from(r in Reply, where: r.ticket_id == ^ctx.ticket_a.id), :count) ==
                 1

        assert Repo.get!(Ticket, ctx.ticket_a.id).first_response_at
      end)
    end

    test "the merchant can deactivate and then delete the user's seat", ctx do
      Tenancy.run("a", fn ->
        revoke(ctx.agent)
        profile = Repo.get_by!(AgentProfile, user_id: ctx.agent.id)

        assert {:ok, deactivated} = Repo.update(change(profile, is_active: false))
        refute deactivated.is_active
        assert {:ok, _} = Repo.delete(deactivated)
        refute Repo.get_by(AgentProfile, user_id: ctx.agent.id)
      end)
    end

    test "the revoked user still cannot be newly assigned", ctx do
      Tenancy.run("a", fn ->
        revoke(ctx.agent)

        assert_raise Tenancy.Error, fn ->
          Repo.update(change(ctx.ticket_a, assigned_to: ctx.agent.id))
        end

        assert_raise Tenancy.Error, fn ->
          Repo.update(change(ctx.ticket_a, requester_id: ctx.b.id))
        end
      end)
    end

    test "one revoked assignee does not stop the SLA sweep for any merchant", ctx do
      past = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)

      Tenancy.run("a", fn ->
        {:ok, t} = AssignmentService.assign(ctx.ticket_a, ctx.agent.id, actor_id: ctx.admin.id)
        TestRepo.update!(change(t, sla_first_response_due_at: past))
      end)

      TestRepo.update!(change(ctx.ticket_b, sla_first_response_due_at: past))
      revoke(ctx.agent)
      Application.put_env(:escalated, :tenant_resolver, CatalogResolver)

      assert [{"a", _}, {"b", _}] = Maintenance.run([], fn _ -> SlaService.check_breaches() end)
      assert TestRepo.get!(Ticket, ctx.ticket_a.id).sla_breached
      assert TestRepo.get!(Ticket, ctx.ticket_b.id).sla_breached
    end
  end

  describe "updates still validate what they change" do
    test "a reference to another merchant's row is refused", ctx do
      Tenancy.run("a", fn ->
        reply =
          Repo.insert!(Reply.changeset(%Reply{}, %{ticket_id: ctx.ticket_a.id, body: "x"}))

        assert_raise Tenancy.Error, fn ->
          Repo.update(change(reply, ticket_id: ctx.ticket_b.id))
        end
      end)
    end

    test "ownership and identity cannot change", ctx do
      Tenancy.run("a", fn ->
        assert_raise Tenancy.Error, fn -> Repo.update(change(ctx.ticket_a, tenant_id: "b")) end

        assert_raise Tenancy.Error, fn ->
          Repo.update(change(ctx.ticket_a, id: ctx.ticket_b.id))
        end
      end)
    end

    test "a delete is still limited to the merchant's own rows", ctx do
      Tenancy.run("a", fn ->
        assert_raise Tenancy.Error, fn -> Repo.delete(ctx.ticket_b) end
      end)

      assert TestRepo.get(Ticket, ctx.ticket_b.id)
    end
  end

  describe "insert_all row values" do
    setup do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      %{now: now}
    end

    defp tag_names, do: TestRepo.all(from(t in Tag, select: t.name))

    test "a query value is refused instead of running unscoped", ctx do
      Tenancy.run("a", fn ->
        foreign = from(t in Ticket, where: t.id == ^ctx.ticket_b.id, select: t.subject)
        legacy = from(t in Ticket, where: t.tenant_id == "", select: t.subject, limit: 1)

        for value <- [foreign, legacy, subquery(foreign)] do
          assert_raise Tenancy.Error, fn ->
            Repo.insert_all(Tag, [%{name: value, inserted_at: ctx.now, updated_at: ctx.now}])
          end
        end
      end)

      refute "B SECRET SUBJECT" in tag_names()
      refute "LEGACY SECRET" in tag_names()
    end

    test "placeholder values are refused", ctx do
      Tenancy.run("a", fn ->
        assert_raise Tenancy.Error, fn ->
          Repo.insert_all(
            Tag,
            [%{name: {:placeholder, :name}, inserted_at: ctx.now, updated_at: ctx.now}],
            placeholders: %{name: "placeholder"}
          )
        end
      end)

      assert tag_names() == []
    end

    test "Multi.insert_all is checked the same way", ctx do
      foreign = from(t in Ticket, where: t.id == ^ctx.ticket_b.id, select: t.subject)

      multi =
        Ecto.Multi.insert_all(Ecto.Multi.new(), :tags, Tag, [
          %{name: foreign, inserted_at: ctx.now, updated_at: ctx.now}
        ])

      Tenancy.run("a", fn ->
        assert_raise Tenancy.Error, fn -> Repo.transaction(multi) end
      end)

      assert tag_names() == []
    end

    test "plain values are still inserted in the current merchant", ctx do
      Tenancy.run("a", fn ->
        assert {1, _} =
                 Repo.insert_all(Tag, [
                   %{name: "plain", inserted_at: ctx.now, updated_at: ctx.now}
                 ])
      end)

      assert [%Tag{tenant_id: "a"}] = TestRepo.all(from(t in Tag, where: t.name == "plain"))
    end
  end
end
