# Run from the Phoenix project with existing compiled dependencies:
# MIX_ENV=test mix run --no-compile --no-start scripts/verify_tenancy_migrations.exs sqlite
# Also accepts postgres or mysql, using ESCALATED_TEST_HOST/PORT/USERNAME/PASSWORD.
# It never starts TestRepo, HostTestRepo, the package application or ExUnit.

defmodule PhoenixTenancyMigrationProbe do
  alias Ecto.Adapters.SQL

  @legacy_version 20_260_802_000_001
  @tenant_version 20_260_930_000_001
  @guest_version 20_260_930_000_002
  @guest_result_version 20_260_930_000_003
  @database_prefix "phoenix_tenancy_probe_20260930_"

  def run(adapter_name) when adapter_name in ["sqlite", "postgres", "mysql"] do
    Logger.configure(level: :warning)
    Application.load(:escalated)
    Application.put_env(:escalated, :tenancy_enabled, false)

    {adapter, application} =
      case adapter_name do
        "sqlite" -> {Ecto.Adapters.SQLite3, :ecto_sqlite3}
        "postgres" -> {Ecto.Adapters.Postgres, :postgrex}
        "mysql" -> {Ecto.Adapters.MyXQL, :myxql}
      end

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(application)
    config = database_config(adapter_name)
    assert_owned_target!(adapter_name, config[:database])
    repo = PhoenixTenancyMigrationProbe.Repo

    Module.create(
      repo,
      quote do
        use Ecto.Repo, otp_app: :phoenix_tenancy_probe, adapter: unquote(adapter)
      end,
      Macro.Env.location(__ENV__)
    )

    Application.put_env(:phoenix_tenancy_probe, repo, config)

    case adapter.storage_up(config) do
      :ok ->
        :ok

      {:error, :already_up} ->
        raise "Probe target already exists; refusing to overwrite #{config[:database]}"

      error ->
        raise "Unable to create disposable probe target: #{inspect(error)}"
    end

    IO.puts("PROBE created #{adapter_name} #{config[:database]}")
    {:ok, pid} = repo.start_link()
    Application.put_env(:escalated, :repo, repo)

    try do
      result = verify!(repo, adapter_name)
      GenServer.stop(pid)
      assert_owned_target!(adapter_name, config[:database])
      :ok = adapter.storage_down(config)
      IO.puts("PROBE_RESULT " <> Jason.encode!(Map.put(result, :cleaned_up, true)))
    rescue
      error ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        IO.puts("PROBE_FAILURE retained disposable database #{config[:database]}")
        reraise error, __STACKTRACE__
    end
  end

  defp verify!(repo, adapter_name) do
    migrations = Path.expand("priv/repo/migrations")
    Ecto.Migrator.run(repo, migrations, :up, to: @legacy_version, log: false)

    legacy_tables =
      Escalated.Tenancy.Tables.entries()
      |> Enum.reject(&(&1.name in ["guest_challenges", "guest_grants"]))
      |> Enum.map(&Escalated.table_name(&1.name))

    check!(length(legacy_tables) == 56, "Expected the fixed 56-table pre-tenancy baseline")

    seeds = seed_legacy!(repo)
    original = snapshots(repo, legacy_tables)
    original_count = original |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
    check!(original_count >= 10, "The upgrade must exercise populated legacy tables")
    IO.puts("PROBE #{adapter_name}: legacy schema seeded with #{original_count} rows")

    Ecto.Migrator.run(repo, migrations, :up, to: @guest_version, log: false)
    verify_guest_result_clearing!(repo, migrations)
    IO.puts("PROBE #{adapter_name}: stored guest proof results cleared on upgrade")

    check!(
      snapshots(repo, legacy_tables, true) == original,
      "Upgrade changed legacy values or relationships"
    )

    for table <- legacy_tables do
      result = SQL.query!(repo, "SELECT tenant_id FROM #{quote_name(repo, table)}", [])
      check!(Enum.all?(result.rows, &(&1 == [""])), "Legacy tenant default incorrect in #{table}")
    end

    expect_sql_error!(
      repo,
      insert_sql(repo, "contacts", Map.put(seeds.contacts, :tenant_id, nil)),
      "tenant_id must remain NOT NULL"
    )

    IO.puts(
      "PROBE #{adapter_name}: populated upgrade preserved every row; default/NOT NULL passed"
    )

    verify_guest_rollback!(repo, migrations, legacy_tables)

    IO.puts(
      "PROBE #{adapter_name}: challenge, grant and global mailbox state each refuse rollback"
    )

    Ecto.Migrator.run(repo, migrations, :down, to: @tenant_version, log: false)
    check!(snapshots(repo, legacy_tables) == original, "Clean downgrade changed legacy rows")

    for table <- legacy_tables do
      columns = SQL.query!(repo, "SELECT * FROM #{quote_name(repo, table)} LIMIT 0", []).columns
      check!("tenant_id" not in columns, "Clean downgrade retained tenant_id on #{table}")
    end

    expect_sql_error!(
      repo,
      insert_sql(repo, "contacts", seeds.contacts),
      "Legacy global unique email was not restored"
    )

    IO.puts(
      "PROBE #{adapter_name}: clean downgrade preserved rows and restored legacy uniqueness"
    )

    Ecto.Migrator.run(repo, migrations, :up, all: true, log: false)

    for {name, values} <-
          Map.take(seeds, [:contacts, :settings, :roles, :permissions, :agent_profiles]) do
      for tenant <- ["Merchant", "merchant"] do
        insert!(repo, to_string(name), Map.put(values, :tenant_id, tenant))
      end

      expect_sql_error!(
        repo,
        insert_sql(repo, to_string(name), Map.put(values, :tenant_id, "Merchant")),
        "Duplicate tenant-local natural key was accepted in #{name}"
      )

      table = quote_name(repo, Escalated.table_name(to_string(name)))

      for tenant <- ["Merchant", "merchant"] do
        result =
          SQL.query!(repo, "SELECT COUNT(*) FROM #{table} WHERE tenant_id = '#{tenant}'", [])

        check!(result.rows == [[1]], "Tenant IDs are not case-sensitive in #{name}")
      end
    end

    IO.puts("PROBE #{adapter_name}: five natural keys isolate case-sensitive tenant IDs")

    assigned = snapshots(repo, legacy_tables)

    refused =
      try do
        Ecto.Migrator.run(repo, migrations, :down, to: @tenant_version, log: false)
        false
      rescue
        error -> String.contains?(Exception.message(error), "Cannot roll back merchant tenancy")
      end

    check!(refused, "Rollback did not refuse assigned tenant rows")

    check!(
      @tenant_version in Ecto.Migrator.migrated_versions(repo),
      "Refused rollback removed migration version"
    )

    check!(
      snapshots(repo, legacy_tables) == assigned,
      "Refused rollback changed tenant data/schema"
    )

    IO.puts(
      "PROBE #{adapter_name}: assigned-row rollback refused without modifying merchant tables"
    )

    %{
      adapter: adapter_name,
      merchant_tables: length(legacy_tables),
      legacy_rows: original_count,
      populated_upgrade: true,
      legacy_defaults_and_not_null: true,
      clean_downgrade: true,
      local_unique_keys_checked: 5,
      case_sensitive_tenants: true,
      guest_state_rollback_refused: true,
      guest_results_cleared: true,
      assigned_rollback_refused: true
    }
  end

  # Rows from before the replay change hold live capabilities in `result`. The
  # upgrade must clear every one of them, in every tenant, and change nothing else.
  defp verify_guest_result_clearing!(repo, migrations) do
    expiry = ~U[2099-01-01 00:00:00Z]
    used = ~U[2026-09-30 00:00:00Z]
    hash = String.duplicate("0", 64)

    rows =
      for {tenant, result} <- [
            {"", %{"guest_access_token" => "live-capability", "ticket_id" => 101}},
            {"merchant", %{"data" => [%{"guest_access_token" => "live-capability"}]}},
            {"merchant", nil}
          ] do
        repo.insert!(%Escalated.Schemas.GuestChallenge{
          tenant_id: tenant,
          email: "probe@example.test",
          purpose: "ticket",
          code_hash: hash,
          attempts: 1,
          expires_at: expiry,
          used_at: if(result, do: used),
          request_hash: if(result, do: hash),
          result: result
        })
      end

    Ecto.Migrator.run(repo, migrations, :up, all: true, log: false)

    check!(
      @guest_result_version in Ecto.Migrator.migrated_versions(repo),
      "Result clearing did not run"
    )

    for row <- rows do
      after_row = repo.get!(Escalated.Schemas.GuestChallenge, row.id)
      check!(is_nil(after_row.result), "A stored guest proof result survived the upgrade")

      check!(
        Map.drop(after_row, [:result, :__meta__]) == Map.drop(row, [:result, :__meta__]),
        "Clearing guest proof results changed another column"
      )

      repo.delete!(after_row)
    end
  end

  defp verify_guest_rollback!(repo, migrations, legacy_tables) do
    expiry = ~U[2099-01-01 00:00:00Z]
    hash = String.duplicate("0", 64)

    guest_tables =
      Enum.map(~w(guest_challenges guest_grants guest_mailbox_budgets), &Escalated.table_name/1)

    merchant_before = snapshots(repo, legacy_tables)

    records = [
      %Escalated.Schemas.GuestChallenge{
        email: "probe@example.test",
        purpose: "ticket",
        code_hash: hash,
        expires_at: expiry
      },
      %Escalated.Schemas.GuestGrant{
        ticket_id: 101,
        purpose: "ticket",
        email_hash: hash,
        nonce_hash: hash,
        expires_at: expiry
      },
      %Escalated.Schemas.GuestMailboxBudget{mailbox_hash: hash, attempts: 3, expires_at: expiry}
    ]

    for record <- records do
      saved = repo.insert!(record)
      guest_before = snapshots(repo, guest_tables)

      refused =
        try do
          Ecto.Migrator.run(repo, migrations, :down, to: @tenant_version, log: false)
          false
        rescue
          error ->
            String.contains?(Exception.message(error), "Cannot roll back verified guest access")
        end

      check!(
        refused,
        "Guest rollback did not refuse populated #{record.__struct__.__schema__(:source)}"
      )

      check!(
        snapshots(repo, guest_tables) == guest_before,
        "Refused rollback changed guest state"
      )

      check!(
        snapshots(repo, legacy_tables) == merchant_before,
        "Guest rollback guard changed merchant data"
      )

      check!(
        @guest_version in Ecto.Migrator.migrated_versions(repo),
        "Guest guard removed its migration version"
      )

      repo.delete!(saved)
    end
  end

  defp seed_legacy!(repo) do
    timestamp = %{inserted_at: "2026-09-30 00:00:00", updated_at: "2026-09-30 00:00:00"}

    seeds = %{
      contacts:
        Map.merge(timestamp, %{
          email: "recipient@example.test",
          name: "Legacy recipient",
          metadata: "{}"
        }),
      settings:
        Map.merge(timestamp, %{
          key: "probe_setting",
          value: "legacy value",
          type: "string",
          group: "general"
        }),
      roles: Map.merge(timestamp, %{slug: "probe_role", name: "Legacy role"}),
      permissions: Map.merge(timestamp, %{slug: "probe.permission", name: "Legacy permission"}),
      agent_profiles:
        Map.merge(timestamp, %{user_id: 42, display_name: "Legacy seat", role: "agent"})
    }

    for {name, values} <- seeds, do: insert!(repo, to_string(name), Map.put(values, :id, 101))

    insert!(
      repo,
      "departments",
      Map.merge(timestamp, %{id: 101, name: "Legacy support", slug: "legacy-support"})
    )

    insert!(
      repo,
      "tickets",
      Map.merge(timestamp, %{
        id: 101,
        reference: "PROBE-LEGACY",
        subject: "Legacy parcel",
        description: "Preserve correspondence",
        contact_id: 101,
        department_id: 101,
        guest_email: "recipient@example.test"
      })
    )

    insert!(
      repo,
      "replies",
      Map.merge(timestamp, %{id: 101, ticket_id: 101, body: "Legacy public reply"})
    )

    insert!(repo, "tags", Map.merge(timestamp, %{id: 101, name: "Legacy tag"}))
    insert!(repo, "ticket_tags", %{ticket_id: 101, tag_id: 101})
    insert!(repo, "role_permissions", %{role_id: 101, permission_id: 101})
    seeds
  end

  defp snapshots(repo, tables, remove_tenant \\ false) do
    Map.new(tables, fn table ->
      result = SQL.query!(repo, "SELECT * FROM #{quote_name(repo, table)}", [])

      rows =
        Enum.map(result.rows, fn values ->
          row = Map.new(Enum.zip(result.columns, values))
          if remove_tenant, do: Map.delete(row, "tenant_id"), else: row
        end)

      {table, Enum.sort(rows)}
    end)
  end

  defp insert!(repo, name, values), do: SQL.query!(repo, insert_sql(repo, name, values), [])

  defp insert_sql(repo, name, values) do
    ordered = Enum.sort(values)
    columns = Enum.map_join(ordered, ",", fn {key, _} -> quote_name(repo, to_string(key)) end)
    literals = Enum.map_join(ordered, ",", fn {_, value} -> literal(value) end)

    "INSERT INTO #{quote_name(repo, Escalated.table_name(name))} (#{columns}) VALUES (#{literals})"
  end

  defp quote_name(repo, value) do
    quote = if repo.__adapter__() == Ecto.Adapters.MyXQL, do: "`", else: "\""
    quote <> String.replace(value, quote, quote <> quote) <> quote
  end

  defp literal(nil), do: "NULL"
  defp literal(value) when is_integer(value), do: Integer.to_string(value)
  defp literal(value) when is_binary(value), do: "'" <> String.replace(value, "'", "''") <> "'"

  defp expect_sql_error!(repo, sql, label) do
    case SQL.query(repo, sql, []) do
      {:error, _} -> :ok
      {:ok, _} -> raise label
    end
  end

  defp check!(true, _message), do: :ok
  defp check!(false, message), do: raise(message)

  defp database_config("sqlite") do
    [
      database: "/tmp/#{@database_prefix}sqlite.db",
      pool_size: 2,
      busy_timeout: 15_000,
      journal_mode: :wal
    ]
  end

  defp database_config(adapter) do
    [
      database: @database_prefix <> adapter,
      hostname: System.fetch_env!("ESCALATED_TEST_HOST"),
      port: String.to_integer(System.fetch_env!("ESCALATED_TEST_PORT")),
      username: System.fetch_env!("ESCALATED_TEST_USERNAME"),
      password: System.fetch_env!("ESCALATED_TEST_PASSWORD"),
      pool_size: 2
    ]
  end

  defp assert_owned_target!("sqlite", database) do
    check!(
      Path.expand(database) == "/tmp/#{@database_prefix}sqlite.db",
      "Unsafe SQLite probe path"
    )
  end

  defp assert_owned_target!(adapter, database) do
    check!(
      database == @database_prefix <> adapter and adapter in ["postgres", "mysql"],
      "Unsafe probe database"
    )
  end
end

[adapter] = System.argv()
PhoenixTenancyMigrationProbe.run(adapter)
