defmodule Escalated.Services.GuestAccessConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox

  alias Escalated.Schemas.{
    Contact,
    GuestChallenge,
    GuestGrant,
    GuestMailboxBudget,
    Ticket,
    TicketActivity
  }

  alias Escalated.Services.{GuestAccess, TicketService}
  alias Escalated.Tenancy
  alias Escalated.Test.GuestAccessHelpers, as: Helpers
  alias Escalated.TestRepo

  # A shared sandbox connection cannot demonstrate competing transactions.
  # These cases commit on independent server connections and clean only their namespace.
  @moduletag skip: Escalated.TestRepo.__adapter__() == Ecto.Adapters.SQLite3

  setup do
    Helpers.configure()

    previous =
      Map.new(
        [:tenancy_enabled, :ticket_reference_generator, :guest_reference_resolver],
        &{&1, Application.fetch_env(:escalated, &1)}
      )

    Application.put_env(:escalated, :tenancy_enabled, true)
    tenant = "guest-race-" <> Ecto.UUID.generate()
    address = tenant <> "@example.test"

    keys =
      for scope <- ["", "|network:unknown"] do
        :crypto.mac(
          :hmac,
          :sha256,
          Escalated.config(:guest_access_secret),
          "mailbox:" <> address <> scope
        )
        |> Base.encode16(case: :lower)
      end

    on_exit(fn ->
      Sandbox.unboxed_run(TestRepo, fn ->
        for schema <- [GuestGrant, GuestChallenge, TicketActivity, Ticket, Contact] do
          TestRepo.delete_all(from(row in schema, where: row.tenant_id == ^tenant))
        end

        TestRepo.delete_all(from(row in GuestMailboxBudget, where: row.mailbox_hash in ^keys))
      end)

      Enum.each(previous, fn
        {name, {:ok, value}} -> Application.put_env(:escalated, name, value)
        {name, :error} -> Application.delete_env(:escalated, name)
      end)
    end)

    %{tenant: tenant, address: address}
  end

  test "a competing request waits for proof commit then replays without another ticket or event",
       %{tenant: tenant, address: address} do
    proof = unboxed(tenant, fn -> Helpers.proof(address) end)
    attrs = %{subject: "Concurrent parcel", description: "Help", guest_email: address}
    parent = self()

    Application.put_env(:escalated, :ticket_reference_generator, fn ->
      send(parent, {:proof_locked, self()})

      receive do
        :allow_reference -> Ticket.generate_reference()
      after
        5000 -> raise "proof owner was not released"
      end
    end)

    first =
      Task.async(fn -> unboxed(tenant, fn -> TicketService.create_guest(proof, attrs) end) end)

    assert_receive {:proof_locked, owner}, 5000

    second =
      Task.async(fn ->
        unboxed(tenant, fn ->
          send(parent, :competitor_started)
          TicketService.create_guest(proof, attrs)
        end)
      end)

    assert_receive :competitor_started, 5000
    assert Task.yield(second, 100) == nil
    send(owner, :allow_reference)
    assert {:ok, first_ticket, first_result} = Task.await(first, 10_000)
    assert {:ok, second_ticket, second_result} = Task.await(second, 10_000)
    assert first_ticket.id == second_ticket.id
    assert second_result["_replayed"] == true

    unboxed(tenant, fn ->
      assert {:ok, _, grant} = GuestAccess.resolve(first_result["guest_access_token"])
      assert {:ok, _, ^grant} = GuestAccess.resolve(second_result["guest_access_token"])
      assert Escalated.repo().aggregate(Ticket, :count) == 1
      assert Escalated.repo().aggregate(TicketActivity, :count) == 1
      assert Escalated.repo().aggregate(GuestGrant, :count) == 1
    end)
  end

  test "parallel invalid codes atomically stop at five attempts", %{
    tenant: tenant,
    address: address
  } do
    proof = unboxed(tenant, fn -> Helpers.proof(address) end)
    wrong = Map.put(proof, "verification_code", "wrong")

    results =
      1..7
      |> Task.async_stream(
        fn _ ->
          unboxed(tenant, fn ->
            GuestAccess.consume(wrong, "ticket", %{}, fn -> flunk("invalid proof consumed") end)
          end)
        end,
        max_concurrency: 7,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:error, :verification}}, &1))

    unboxed(tenant, fn ->
      assert Escalated.repo().get!(GuestChallenge, proof["verification_id"]).attempts == 5

      assert {:error, :verification} =
               GuestAccess.consume(proof, "ticket", %{}, fn ->
                 flunk("exhausted proof consumed")
               end)
    end)
  end

  test "parallel delivery requests cannot exceed the persistent mailbox budget", %{
    tenant: tenant,
    address: address
  } do
    results =
      1..6
      |> Task.async_stream(
        fn _ ->
          unboxed(tenant, fn -> GuestAccess.challenge(address, "ticket") end)
        end,
        max_concurrency: 6,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.count(results, &match?({:ok, {:ok, _}}, &1)) == 3
    assert Enum.count(results, &match?({:ok, {:error, :rate_limited}}, &1)) == 3
    unboxed(tenant, fn -> assert Escalated.repo().aggregate(GuestChallenge, :count) == 3 end)
  end

  test "competing verified lookups both issue a grant for a ticket that had none", %{
    tenant: tenant,
    address: address
  } do
    # A guest ticket created outside the verified flow (agent, inbound or legacy)
    # has no grant row until its first lookup.
    ticket =
      unboxed(tenant, fn ->
        {:ok, ticket} =
          Escalated.repo().transaction(fn ->
            {:ok, ticket} =
              TicketService.insert(%{
                subject: "Inbound",
                description: "Help",
                guest_email: address,
                priority: "medium"
              })

            ticket
          end)

        ticket
      end)

    first_proof = unboxed(tenant, fn -> Helpers.proof(address, "lookup") end)
    second_proof = unboxed(tenant, fn -> Helpers.proof(address, "lookup") end)
    parent = self()
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    # The first lookup reads inside its proof transaction, then pauses before
    # issuing, while the second issues and commits the ticket's first grant.
    Application.put_env(:escalated, :guest_reference_resolver, fn _, _, _ ->
      if Agent.get_and_update(calls, &{&1, &1 + 1}) == 0 do
        send(parent, {:first_waiting, self()})

        receive do
          :go -> :ok
        after
          5000 -> raise "first lookup was not released"
        end
      end

      []
    end)

    lookup = fn proof ->
      unboxed(tenant, fn ->
        GuestAccess.lookup(Map.put(proof, "reference", ticket.reference))
      end)
    end

    first = Task.async(fn -> lookup.(first_proof) end)
    assert_receive {:first_waiting, owner}, 5000
    assert {:ok, %{"data" => [_]}} = lookup.(second_proof)
    send(owner, :go)
    assert {:ok, %{"data" => [renewed]}} = Task.await(first, 10_000)

    unboxed(tenant, fn ->
      assert Escalated.repo().aggregate(GuestGrant, :count) == 1
      assert {:ok, _, _} = GuestAccess.resolve(renewed["guest_access_token"])
    end)
  end

  defp unboxed(tenant, callback),
    do: Sandbox.unboxed_run(TestRepo, fn -> Tenancy.run(tenant, callback) end)
end
