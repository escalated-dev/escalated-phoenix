defmodule Escalated.Services.TicketCreateOutsideTransactionTest do
  @moduledoc """
  Ticket creation as a production request reaches it: on a plain connection
  with no enclosing transaction.

  `Escalated.DataCase` wraps every test in a sandbox transaction, so a write
  that only works inside one (a PostgreSQL savepoint, for example) passes
  there and fails for every real customer, API, inbound-email and chat
  request. These cases therefore run through `Sandbox.unboxed_run/2`, commit
  for real, and clean up only the rows they created.
  """
  use ExUnit.Case, async: false
  import Ecto.Query
  alias Ecto.Adapters.SQL.Sandbox
  alias Escalated.Schemas.{Contact, Ticket, TicketActivity}
  alias Escalated.Services.TicketService
  alias Escalated.TestRepo

  setup do
    tag = "outside-tx-" <> Ecto.UUID.generate()
    email = tag <> "@example.test"
    taken = "ESC-2609-" <> String.slice(String.upcase(Ecto.UUID.generate()), 0, 8)

    on_exit(fn ->
      Application.delete_env(:escalated, :ticket_reference_generator)

      Sandbox.unboxed_run(TestRepo, fn ->
        ids = TestRepo.all(from(t in Ticket, where: t.subject == ^tag, select: t.id))
        TestRepo.delete_all(from(a in TicketActivity, where: a.ticket_id in ^ids))
        TestRepo.delete_all(from(t in Ticket, where: t.id in ^ids))
        TestRepo.delete_all(from(c in Contact, where: c.email == ^email))
      end)
    end)

    %{tag: tag, email: email, taken: taken}
  end

  defp unboxed(fun), do: Sandbox.unboxed_run(TestRepo, fun)

  test "an authenticated requester's ticket is created", %{tag: tag} do
    assert {:ok, %Ticket{id: id}} =
             unboxed(fn ->
               refute TestRepo.in_transaction?()

               TicketService.create(%{
                 subject: tag,
                 description: "d",
                 requester_id: 1,
                 requester_type: "user"
               })
             end)

    assert unboxed(fn -> TestRepo.get(Ticket, id) end)
  end

  test "a guest ticket creates its contact and the ticket", %{tag: tag, email: email} do
    assert {:ok, %Ticket{id: id, contact_id: contact_id}} =
             unboxed(fn ->
               TicketService.create(%{subject: tag, description: "d", guest_email: email})
             end)

    assert contact_id

    unboxed(fn ->
      assert TestRepo.get(Ticket, id)
      assert TestRepo.get_by!(Contact, email: email).id == contact_id
    end)
  end

  test "a taken reference is still retried under a fresh one", %{tag: tag, taken: taken} do
    fresh = taken <> "F"

    unboxed(fn ->
      %Ticket{reference: taken}
      |> Ticket.changeset(%{subject: tag, description: "first"})
      |> TestRepo.insert!()
    end)

    {:ok, agent} = Agent.start_link(fn -> [taken, fresh] end)

    Application.put_env(:escalated, :ticket_reference_generator, fn ->
      Agent.get_and_update(agent, fn
        [last] -> {last, [last]}
        [next | rest] -> {next, rest}
      end)
    end)

    assert {:ok, %Ticket{reference: ^fresh}} =
             unboxed(fn -> TicketService.create(%{subject: tag, description: "second"}) end)
  end
end
