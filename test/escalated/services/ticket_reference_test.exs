defmodule Escalated.Services.TicketReferenceTest do
  @moduledoc """
  A generated reference that is already taken must not lose the ticket.

  `tickets.reference` has a unique index and the reference is random, so two
  tickets can draw the same one. When the insert hits that index, the ticket is
  inserted again under a fresh reference, a few times at most, on every path
  that inserts a ticket. The generator is swapped through
  `:ticket_reference_generator` so the collision happens on purpose instead of
  by chance.
  """
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.{ChatSessionService, TicketService}

  @taken "ESC-2609-TAKEN000"
  @fresh "ESC-2609-FRESH000"

  defp repo, do: Escalated.repo()

  setup do
    on_exit(fn -> Application.delete_env(:escalated, :ticket_reference_generator) end)
    :ok
  end

  defp insert_ticket!(reference) do
    %Ticket{reference: reference}
    |> Ticket.changeset(%{subject: "Already here", description: "First"})
    |> repo().insert!()
  end

  # Hands out `references` in order, repeating the last one, and counts calls.
  defp generate_in_order(references) do
    {:ok, agent} = Agent.start_link(fn -> {references, 0} end)

    Application.put_env(:escalated, :ticket_reference_generator, fn ->
      Agent.get_and_update(agent, fn
        {[last], calls} -> {last, {[last], calls + 1}}
        {[next | rest], calls} -> {next, {rest, calls + 1}}
      end)
    end)

    agent
  end

  defp calls(agent), do: Agent.get(agent, fn {_, calls} -> calls end)

  describe "TicketService.create/1" do
    test "inserts under a fresh reference when the generated one is taken" do
      insert_ticket!(@taken)
      generator = generate_in_order([@taken, @fresh])

      assert {:ok, ticket} = TicketService.create(%{subject: "Printer", description: "Jammed"})
      assert ticket.reference == @fresh
      assert calls(generator) == 2
      assert repo().get_by!(Ticket, reference: @fresh).id == ticket.id
    end

    test "gives up after three attempts and returns the reference error" do
      insert_ticket!(@taken)
      generator = generate_in_order([@taken])

      assert {:error, changeset} =
               TicketService.create(%{subject: "Printer", description: "Jammed"})

      assert {"has already been taken", opts} = changeset.errors[:reference]
      assert opts[:constraint] == :unique
      assert calls(generator) == 3
      assert repo().aggregate(Ticket, :count) == 1
    end

    test "does not retry a ticket that fails validation" do
      generator = generate_in_order([@fresh])

      assert {:error, changeset} = TicketService.create(%{subject: "No description"})
      assert changeset.errors[:description]
      assert calls(generator) == 1
    end
  end

  describe "the other paths that insert a ticket" do
    test "split_ticket/3 inserts under a fresh reference" do
      insert_ticket!(@taken)
      {:ok, original} = TicketService.create(%{subject: "Two problems", description: "Both"})
      {:ok, reply} = TicketService.reply(original, %{body: "The second problem"})
      generator = generate_in_order([@taken, @fresh])

      assert {:ok, split} = TicketService.split_ticket(original, reply)
      assert split.reference == @fresh
      assert calls(generator) == 2
    end

    test "a live chat's ticket is inserted under a fresh reference" do
      insert_ticket!(@taken)
      generator = generate_in_order([@taken, @fresh])

      assert {:ok, ticket, _session} =
               ChatSessionService.start_session(%{guest_name: "Visitor", message: "Hello"})

      assert ticket.reference == @fresh
      assert calls(generator) == 2
    end
  end

  describe "TicketService.find/1" do
    test "finds tickets under the old six-character references and the new eight" do
      for reference <- ["ESC-2604-ABC123", "ESC-2609-7KQ2M9XH"] do
        ticket = insert_ticket!(reference)
        assert TicketService.find(reference).id == ticket.id
      end
    end
  end
end
