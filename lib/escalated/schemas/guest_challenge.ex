defmodule Escalated.Schemas.GuestChallenge do
  @moduledoc false
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}guest_challenges" do
    field :tenant_id, :string, default: ""
    field :email, :string, redact: true
    field :purpose, :string
    field :code_hash, :string, redact: true
    field :attempts, :integer, default: 0
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :request_hash, :string
    field :result, :map, redact: true
    timestamps(type: :utc_datetime)
  end
end
