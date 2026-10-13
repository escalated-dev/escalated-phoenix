defmodule Escalated.Repo.Migrations.AddTicketAccess do
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  def up do
    alter table(@prefix <> "tickets") do
      add :account_type, :string, identity_options()
      add :account_id, :string, identity_options()
    end

    create index(@prefix <> "tickets", [:account_type, :account_id], name: index_name("account"))

    alter table(@prefix <> "sla_policies") do
      add :department_id,
          references(@prefix <> "departments", on_delete: :restrict, name: index_name("sla_fk"))

      add :ticket_type, :string, size: 32
    end

    create index(@prefix <> "sla_policies", [:department_id, :ticket_type],
             name: index_name("sla")
           )

    create table(@prefix <> "department_agent") do
      add :tenant_id, :string, [default: "", null: false] ++ identity_options()

      add :department_id, references(@prefix <> "departments", on_delete: :delete_all),
        null: false

      add :agent_id, @user_id_type, agent_options()
    end

    create unique_index(@prefix <> "department_agent", [:tenant_id, :department_id, :agent_id],
             name: index_name("membership")
           )
  end

  def down do
    drop table(@prefix <> "department_agent")
    # MySQL reuses the composite index to enforce this FK. Drop the FK first.
    if repo().__adapter__() == Ecto.Adapters.MyXQL do
      drop constraint(@prefix <> "sla_policies", index_name("sla_fk"))
    end

    drop index(@prefix <> "sla_policies", [:department_id, :ticket_type], name: index_name("sla"))

    alter table(@prefix <> "sla_policies") do
      remove :department_id
      remove :ticket_type
    end

    drop index(@prefix <> "tickets", [:account_type, :account_id], name: index_name("account"))

    alter table(@prefix <> "tickets") do
      remove :account_type
      remove :account_id
    end
  end

  defp identity_options do
    collation =
      case repo().__adapter__() do
        Ecto.Adapters.MyXQL -> "utf8mb4_bin"
        Ecto.Adapters.Postgres -> "C"
        _ -> "BINARY"
      end

    [size: 191, collation: collation]
  end

  defp agent_options do
    if @user_id_type == :string, do: [null: false] ++ identity_options(), else: [null: false]
  end

  defp index_name(purpose) do
    hash = :crypto.hash(:sha256, @prefix <> purpose) |> Base.encode16(case: :lower)
    "escalated_access_" <> binary_part(hash, 0, 24)
  end
end
