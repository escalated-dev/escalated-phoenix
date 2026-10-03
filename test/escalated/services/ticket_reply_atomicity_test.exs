defmodule Escalated.Services.TicketReplyAtomicityTest do
  @moduledoc """
  A reply and the ticket update it causes (first response time) are saved
  together or not at all, and hooks fire only for a saved reply. Otherwise a
  failed update left a reply behind that the caller was told had failed, and a
  retry posted it twice.
  """
  use Escalated.DataCase, async: false
  import Ecto.Query

  alias Escalated.Schemas.{Reply, Ticket, TicketActivity}
  alias Escalated.Services.TicketService
  alias Escalated.{Tenancy, TestRepo}

  defmodule CapturePlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "reply-capture"

    @impl true
    def handle_action(hook, args) do
      case Application.get_env(:escalated, :test_pid) do
        pid when is_pid(pid) -> send(pid, {:hook, hook, args})
        _ -> :ok
      end
    end
  end

  defmodule Resolver do
    @moduledoc false
    def member?(_, _), do: true
    def reference?(_, _, _), do: true
    def scope_users(query, _tenant), do: query
  end

  @keys [:plugins, :test_pid, :tenancy_enabled, :tenant_resolver]

  setup do
    previous = Map.new(@keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :plugins, [CapturePlugin])
    Application.put_env(:escalated, :test_pid, self())
    {:ok, _} = Escalated.Plugins.activate("reply-capture")

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  defp saved_replies(ticket),
    do: TestRepo.aggregate(from(r in Reply, where: r.ticket_id == ^ticket.id), :count)

  defp reply_activities(ticket) do
    TestRepo.aggregate(
      from(a in TicketActivity, where: a.ticket_id == ^ticket.id and a.action == "reply_added"),
      :count
    )
  end

  test "a successful reply saves the reply and the first response time, then fires hooks" do
    {:ok, ticket} = TicketService.create(%{subject: "Hi", description: "Body"})

    assert {:ok, %Reply{}} = TicketService.reply(ticket, %{body: "Answer", author_id: 7})
    assert saved_replies(ticket) == 1
    assert reply_activities(ticket) == 1
    assert TestRepo.get!(Ticket, ticket.id).first_response_at
    assert_received {:hook, "ticket_replied", [_reply, _ticket]}
  end

  test "a ticket update that is refused keeps no reply and fires no hook" do
    {:ok, ticket} = TicketService.create(%{subject: "Hi", description: "Body"})
    # A stale struct whose update fails validation.
    stale = %{ticket | subject: nil}

    assert {:error, %Ecto.Changeset{}} =
             TicketService.reply(stale, %{body: "Answer", author_id: 7})

    assert saved_replies(ticket) == 0
    assert reply_activities(ticket) == 0
    refute TestRepo.get!(Ticket, ticket.id).first_response_at
    refute_received {:hook, "ticket_replied", _}
  end

  test "a ticket update that raises keeps no reply and fires no hook" do
    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, Resolver)

    Tenancy.run("merchant-a", fn ->
      {:ok, ticket} = TicketService.create(%{subject: "Hi", description: "Body"})
      # The reply's ticket_id is this merchant's ticket, but the struct handed in
      # claims another merchant, so the scoped ticket update is denied.
      foreign = %{ticket | tenant_id: "merchant-b"}

      assert_raise Tenancy.Error, fn ->
        TicketService.reply(foreign, %{body: "Answer", author_id: 7})
      end

      assert saved_replies(ticket) == 0
      assert reply_activities(ticket) == 0
    end)

    refute_received {:hook, "ticket_replied", _}
  end
end
