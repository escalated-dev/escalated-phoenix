defmodule Escalated.Repo.Migrations.CreateRoleUser do
  @moduledoc """
  Which users hold which Escalated roles (`Escalated.Schemas.RoleUser`), as
  escalated-laravel's `role_user`. A user's permissions are the union of
  their roles' permissions while roles & permissions is switched on
  (ADR 2026-10-29-configurable-access-features).

  A new table, so existing installs are unaffected: nothing reads it while
  the switch is off.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  def change do
    create table(@prefix <> "role_user", primary_key: false) do
      add :tenant_id, :string, tenant_options()
      add :role_id, references(@prefix <> "roles", on_delete: :delete_all), null: false
      add :user_id, @user_id_type, null: false
    end

    create unique_index(@prefix <> "role_user", [:tenant_id, :role_id, :user_id],
             name: index_name("unique")
           )

    create index(@prefix <> "role_user", [:tenant_id, :user_id], name: index_name("user"))
    create index(@prefix <> "role_user", [:role_id], name: index_name("role"))
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
      :crypto.hash(:sha256, @prefix <> "role_user:" <> purpose) |> Base.encode16(case: :lower)

    "escalated_roleusr_" <> binary_part(hash, 0, 24)
  end
end
