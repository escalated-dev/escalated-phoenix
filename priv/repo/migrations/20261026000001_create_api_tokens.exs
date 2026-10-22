defmodule Escalated.Repo.Migrations.CreateApiTokens do
  @moduledoc """
  API tokens (`Escalated.Schemas.ApiToken`), as escalated-laravel's
  `api_tokens`: a name, the owner (a host user key), the SHA-256 digest of
  the token (the token itself is shown once and never stored), its abilities,
  when and from where it was last used, and an optional expiry.

  The digest is unique per tenant namespace. A new table, so existing installs
  are unaffected; the API only accepts these tokens once the host sets
  `config :escalated, api_tokens_enabled: true`.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  def change do
    create table(@prefix <> "api_tokens") do
      add :tenant_id, :string, tenant_options()
      add :user_id, @user_id_type, null: false
      add :name, :string, size: 255, null: false
      add :token, :string, size: 64, null: false
      add :abilities, Escalated.Migration.list_type(:string)
      add :last_used_at, :utc_datetime
      add :last_used_ip, :string, size: 45
      add :expires_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(@prefix <> "api_tokens", [:tenant_id, :token],
             name: @prefix <> "api_tokens_token_index"
           )

    create index(@prefix <> "api_tokens", [:tenant_id, :user_id], name: index_name("user"))
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
      :crypto.hash(:sha256, @prefix <> "api_tokens:" <> purpose) |> Base.encode16(case: :lower)

    "escalated_apitok_" <> binary_part(hash, 0, 24)
  end
end
