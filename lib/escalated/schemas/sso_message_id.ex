defmodule Escalated.Schemas.SsoMessageId do
  @moduledoc """
  A single-use SSO message ID (`Escalated.Sso.MessageIds`): a JWT `jti` that
  has been accepted, kept until `expires_at` (Unix seconds) so it cannot be
  used again.
  """
  use Ecto.Schema

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}sso_message_ids" do
    field :tenant_id, :string, default: ""
    field :kind, :string
    field :message_id, :string
    field :expires_at, :integer
  end
end
