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
        [:tenancy_enabled, :ticket_reference_generator],
        &{&1, Application.fetch_env(:escalated, &1)}
      )

    Application.put_env(:escalated, :tenancy_enabled, true)
    tenant = "guest-race-" <> Ecto.UUID.generate()
    address = tenant <> "@example.test"

    key =
      :crypto.mac(:hmac, :sha256, Escalated.config(:guest_access_secret), "mailbox:" <> address)
      |> Base.encode16(case: :lower)

    on_exit(fn ->
      Sandbox.unboxed_run(TestRepo, fn ->
        for schema <- [GuestGrant, GuestChallenge, TicketActivity, Ticket, Contact] do
          TestRepo.delete_all(from(row in schema, where: row.tenant_id == ^tenant))
        end

        TestRepo.delete_all(from(row in GuestMailboxBudget, where: row.mailbox_hash == ^key))
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
    assert first_result["guest_access_token"] == second_result["guest_access_token"]

    unboxed(tenant, fn ->
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

  defp unboxed(tenant, callback),
    do: Sandbox.unboxed_run(TestRepo, fn -> Tenancy.run(tenant, callback) end)
end
