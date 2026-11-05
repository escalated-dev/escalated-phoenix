defmodule Escalated.Schemas.AgentNotification do
  @moduledoc """
  An agent's in-app notification (ADR 2026-11-05-agent-panel-data). `data`
  carries the ticket id and what the title needs; the feed builds each item
  when it is read, so a ticket the agent can no longer view is redacted.
  """
  use Ecto.Schema

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "#{@prefix}notifications" do
    field :tenant_id, :string, default: ""
    field :user_id, :string
    field :type, :string
    field :data, :map, default: %{}
    field :read_at, :utc_datetime
    field :inserted_at, :utc_datetime
  end
end
