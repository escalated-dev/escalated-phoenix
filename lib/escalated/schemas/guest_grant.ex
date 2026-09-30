defmodule Escalated.Schemas.GuestGrant do
  @moduledoc false
  use Ecto.Schema

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}guest_grants" do
    field :tenant_id, :string, default: ""
    field :ticket_id, :integer
    field :purpose, :string
    field :email_hash, :string, redact: true
    field :nonce_hash, :string, redact: true
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end
end
