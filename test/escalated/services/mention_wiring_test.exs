defmodule Escalated.Services.MentionWiringTest.User do
  @moduledoc false
  use Ecto.Schema

  schema "mention_test_users" do
    field :name, :string
    field :email, :string
    field :is_agent, :boolean, default: false
    field :is_admin, :boolean, default: false
  end
end

defmodule Escalated.Services.MentionWiringTest do
  @moduledoc """
  End-to-end coverage for functional @mentions: an internal note naming an
  agent resolves the handle to that host user, persists a `Mention` row, and
  fires the `agent_mentioned` notification hook. Unknown handles are ignored,
  public replies never mention, and an author naming themselves is skipped.

  Uses a throwaway `mention_test_users` table (the package abstracts the host
  user table, so tests supply one) created inside the sandbox transaction.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query
  import Plug.Test

  alias Escalated.Controllers.Admin.AgentSearchController
  alias Escalated.Schemas.Mention
  alias Escalated.Services.MentionService
  alias Escalated.Services.MentionWiringTest.User
  alias Escalated.Services.TicketService

  @create_users """
  CREATE TABLE IF NOT EXISTS mention_test_users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    email TEXT,
    is_agent INTEGER DEFAULT 0,
    is_admin INTEGER DEFAULT 0
  )
  """

  setup do
    repo = Escalated.repo()
    Ecto.Adapters.SQL.query!(repo, @create_users, [])

    saved = %{
      user_schema: Application.get_env(:escalated, :user_schema),
      hooks: Application.get_env(:escalated, :hooks)
    }

    pid = self()

    Application.put_env(:escalated, :user_schema, User)

    Application.put_env(:escalated, :hooks, %{
      "agent_mentioned" => [
        fn mention, _reply, _ticket -> send(pid, {:mentioned, mention.user_id}) end
      ]
    })

    on_exit(fn -> Enum.each(saved, fn {key, value} -> restore(key, value) end) end)
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:escalated, key)
  defp restore(key, value), do: Application.put_env(:escalated, key, value)

  defp insert_user!(attrs), do: Escalated.repo().insert!(struct(User, attrs))

  defp create_ticket! do
    {:ok, ticket} =
      TicketService.create(%{subject: "S", description: "B", status: "open", priority: "medium"})

    ticket
  end

  defp mentions_for(reply_id) do
    Escalated.repo().all(from(m in Mention, where: m.reply_id == ^reply_id))
  end

  describe "resolve_mentions/1" do
    test "matches by display name and by email, dropping unknown handles" do
      agent = insert_user!(%{name: "agent", email: "agent@example.com", is_agent: true})
      jane = insert_user!(%{name: "Jane Doe", email: "jane@example.com", is_agent: true})

      ids = MentionService.resolve_mentions(["agent", "jane@example.com", "ghost"])

      assert agent.id in ids
      assert jane.id in ids
      assert length(ids) == 2
    end

    test "returns [] when nothing resolves" do
      assert MentionService.resolve_mentions(["nobody"]) == []
      assert MentionService.resolve_mentions([]) == []
    end
  end

  describe "internal note @mentions" do
    test "persists a mention resolved to the agent and fires the notification hook" do
      agent = insert_user!(%{name: "agent", email: "agent@example.com", is_agent: true})
      ticket = create_ticket!()

      {:ok, reply} =
        TicketService.reply(ticket, %{
          body: "hey @agent take a look",
          is_internal: true,
          author_id: 999
        })

      assert [%Mention{} = mention] = mentions_for(reply.id)
      assert mention.user_id == agent.id

      assert_received {:mentioned, notified_id}
      assert notified_id == agent.id
    end

    test "the same agent named twice yields a single mention" do
      insert_user!(%{name: "agent", email: "agent@example.com", is_agent: true})
      ticket = create_ticket!()

      {:ok, reply} =
        TicketService.reply(ticket, %{
          body: "@agent @agent hurry",
          is_internal: true,
          author_id: 999
        })

      assert length(mentions_for(reply.id)) == 1
    end

    test "unknown handles are ignored — no mention, no notification" do
      insert_user!(%{name: "agent", email: "agent@example.com", is_agent: true})
      ticket = create_ticket!()

      {:ok, reply} =
        TicketService.reply(ticket, %{body: "cc @nobody", is_internal: true, author_id: 999})

      assert mentions_for(reply.id) == []
      refute_received {:mentioned, _}
    end

    test "an author mentioning themselves is skipped" do
      agent = insert_user!(%{name: "agent", email: "agent@example.com", is_agent: true})
      ticket = create_ticket!()

      {:ok, reply} =
        TicketService.reply(ticket, %{
          body: "note to self @agent",
          is_internal: true,
          author_id: agent.id
        })

      assert mentions_for(reply.id) == []
      refute_received {:mentioned, _}
    end
  end

  describe "public replies" do
    test "do not create mentions or notify (only internal notes mention)" do
      insert_user!(%{name: "agent", email: "agent@example.com", is_agent: true})
      ticket = create_ticket!()

      {:ok, reply} =
        TicketService.reply(ticket, %{body: "hi @agent", is_internal: false, author_id: 999})

      assert mentions_for(reply.id) == []
      refute_received {:mentioned, _}
    end
  end

  describe "agent_suggestions/1" do
    test "returns matching agents shaped for the composer, excluding non-agents" do
      insert_user!(%{name: "Agatha", email: "agatha@example.com", is_agent: true})
      insert_user!(%{name: "Customer", email: "cust@example.com", is_agent: false})

      assert [%{id: _, name: "Agatha", email: "agatha@example.com"}] =
               MentionService.agent_suggestions("aga")
    end

    test "is empty for a blank query" do
      assert MentionService.agent_suggestions("") == []
      assert MentionService.agent_suggestions("   ") == []
    end
  end

  describe "AgentSearchController" do
    test "search/2 returns matching agents as JSON" do
      insert_user!(%{name: "Agatha", email: "agatha@example.com", is_agent: true})

      conn = AgentSearchController.search(conn(:get, "/"), %{"q" => "aga"})

      assert conn.status == 200
      names = conn.resp_body |> Jason.decode!() |> Enum.map(& &1["name"])
      assert "Agatha" in names
    end

    test "search/2 returns an empty list for a blank query" do
      conn = AgentSearchController.search(conn(:get, "/"), %{"q" => ""})

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == []
    end
  end
end
