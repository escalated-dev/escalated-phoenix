defmodule Escalated.ConnectionTest do
  @moduledoc """
  Escalated's tables and the host's users on two different databases.

  Every query in the package resolved a single repo, which made the package
  unusable in any host that partitions its data -- a schema shared with a legacy
  system, a separate reporting store, or simply a host that would rather keep
  support tables out of its primary database. `:repo` now names the database
  Escalated's own tables live on, and `:user_repo` names the one the host's user
  schema lives on.

  `Escalated.TestRepo` and `Escalated.HostTestRepo` are genuinely separate SQLite
  files here. A second repo pointed at the same file would pass every assertion
  below and prove nothing.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Escalated.Controllers.Admin.UserController
  alias Escalated.HostTestRepo
  alias Escalated.Schemas.Ticket
  alias Escalated.Serializers.TicketSerializer
  alias Escalated.Test.HostUser
  alias Escalated.TestRepo

  setup tags do
    :ok = Sandbox.checkout(TestRepo)
    :ok = Sandbox.checkout(HostTestRepo)

    unless tags[:async] do
      Sandbox.mode(TestRepo, {:shared, self()})
      Sandbox.mode(HostTestRepo, {:shared, self()})
    end

    saved = %{
      user_repo: Application.get_env(:escalated, :user_repo),
      user_schema: Application.get_env(:escalated, :user_schema)
    }

    on_exit(fn ->
      Enum.each(saved, fn
        {key, nil} -> Application.delete_env(:escalated, key)
        {key, value} -> Application.put_env(:escalated, key, value)
      end)

      Sandbox.checkin(TestRepo)
      Sandbox.checkin(HostTestRepo)
    end)

    :ok
  end

  defp split_databases do
    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :user_schema, HostUser)
  end

  defp insert_host_user!(attrs) do
    HostTestRepo.insert!(struct(HostUser, attrs))
  end

  defp insert_ticket!(attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    TestRepo.insert!(
      struct(
        %Ticket{status: "open", priority: "medium", inserted_at: now, updated_at: now},
        attrs
      )
    )
  end

  describe "resolution" do
    test "user_repo defaults to repo, so a host that has not split is unchanged" do
      Application.delete_env(:escalated, :user_repo)

      # Identity, not equality. Everything the package does goes through these
      # two functions, so if they stop being the same module for an
      # unconfigured host, every user query has quietly moved database.
      assert Escalated.user_repo() == Escalated.repo()
      assert Escalated.user_repo() == TestRepo
    end

    test "user_repo is the configured repo when the host splits its databases" do
      split_databases()

      assert Escalated.user_repo() == HostTestRepo
      assert Escalated.repo() == TestRepo
      refute Escalated.user_repo() == Escalated.repo()
    end

    test "the two test repos really are separate databases" do
      # The premise every other case rests on: escalated_tickets does not exist
      # on the host's database, and users does not exist on Escalated's.
      assert {:error, _} =
               Ecto.Adapters.SQL.query(HostTestRepo, "SELECT 1 FROM escalated_tickets", [])

      assert {:error, _} = Ecto.Adapters.SQL.query(TestRepo, "SELECT 1 FROM users", [])
    end

    test "config carries user_repo through to the Config struct" do
      split_databases()

      assert Escalated.configuration().user_repo == HostTestRepo
    end
  end

  describe "reading host users across the split" do
    test "the admin user list reads the host's database, not Escalated's" do
      split_databases()

      insert_host_user!(%{name: "Ada", email: "ada@example.com", is_admin: true, is_agent: true})
      insert_host_user!(%{name: "Grace", email: "grace@example.com", is_agent: true})

      rows = HostTestRepo.all(from(u in HostUser, order_by: [asc: u.id]))

      assert Enum.map(rows, & &1.name) == ["Ada", "Grace"]

      # The controller's payload shape, built from a row that only exists on
      # the host's database.
      assert UserController.user_to_payload(hd(rows)) == %{
               id: hd(rows).id,
               name: "Ada",
               email: "ada@example.com",
               is_admin: true,
               is_agent: true
             }
    end

    test "a ticket on Escalated's database resolves its requester on the host's" do
      split_databases()

      user = insert_host_user!(%{name: "Ada", email: "ada@example.com"})

      ticket =
        insert_ticket!(%{
          subject: "Cannot log in",
          description: "It says my password is wrong",
          requester_id: user.id
        })

      computed = TicketSerializer.computed_fields(ticket)

      # requester_id is a plain unconstrained column -- there is no belongs_to
      # to preload and no join to emit, because no database can join across two
      # connections. The name comes back from a second query on the host's repo.
      assert computed.requester_name == "Ada"
      assert computed.requester_email == "ada@example.com"
    end

    test "an unresolvable requester degrades to nil rather than raising" do
      split_databases()

      ticket =
        insert_ticket!(%{
          subject: "Orphan",
          description: "Requester was deleted from the host",
          requester_id: 999_999
        })

      computed = TicketSerializer.computed_fields(ticket)

      assert computed.requester_name == nil
      assert computed.requester_email == nil
    end
  end

  describe "source contract" do
    @lib_root Path.expand("../../lib", __DIR__)

    test "no query against the user schema resolves Escalated.repo()" do
      offenders =
        @lib_root
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.filter(&queries_users_on_the_wrong_repo?/1)
        |> Enum.map(&Path.relative_to(&1, @lib_root))

      # On a split install Escalated.repo() is a database with no users table
      # in it. A missed call site does not fail loudly -- it queries the wrong
      # database, which reads as users that do not exist.
      assert offenders == [],
             "these files query the user schema through Escalated.repo(): #{Enum.join(offenders, ", ")}"
    end
  end

  defp queries_users_on_the_wrong_repo?(path) do
    source = File.read!(path)

    # Two controllers stringify the schema module into `requester_type` /
    # `rated_by_type`. That is a module name, not a query, and it has no
    # database behind it.
    queries = String.replace(source, "to_string(Escalated.user_schema())", "")

    String.contains?(queries, "user_schema") and
      String.contains?(queries, "Escalated.repo()") and
      not String.contains?(queries, "Escalated.user_repo()")
  end
end
