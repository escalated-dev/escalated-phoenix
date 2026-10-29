defmodule Escalated.Repo.Migrations.CreateSsoMessageIds do
  @moduledoc """
  Single-use SSO message IDs (ADR 2026-10-29-configurable-access-features):
  JWT `jti`s Escalated has accepted (`kind` `jwt`), and the SAML request and
  assertion IDs the ADR keeps in the same table. `expires_at` is Unix
  seconds; rows are pruned once expired. Unique on tenant, kind and ID, so a
  replay loses the race even between two requests at once.

  A new table, so existing installs are unaffected. Created the same way on
  SQLite, PostgreSQL and MySQL.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    create table(@prefix <> "sso_message_ids") do
      add :tenant_id, :string, tenant_options()
      add :kind, :string, size: 32, null: false
      add :message_id, :string, size: 191, null: false
      add :expires_at, :bigint, null: false
    end

    create unique_index(@prefix <> "sso_message_ids", [:tenant_id, :kind, :message_id],
             name: index_name("unique")
           )

    create index(@prefix <> "sso_message_ids", [:expires_at], name: index_name("expires"))
  end

  defp tenant_options do
    opts = [size: 128, null: false, default: ""]

    if repo().__adapter__() == Ecto.Adapters.MyXQL,
      do: Keyword.put(opts, :collation, "utf8mb4_bin"),
      else: opts
  end

  # Bounded names also work with a custom prefix and PostgreSQL's 63-byte cap.
  defp index_name(purpose) do
    hash =
      :crypto.hash(:sha256, @prefix <> "sso_message_ids:" <> purpose)
      |> Base.encode16(case: :lower)

    "escalated_ssomsg_" <> binary_part(hash, 0, 24)
  end
end
