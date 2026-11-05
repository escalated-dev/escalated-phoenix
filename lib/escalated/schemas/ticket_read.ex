defmodule Escalated.Schemas.TicketRead do
  @moduledoc """
  When an agent last read a ticket (ADR 2026-11-05-agent-panel-data). A null
  `last_read_at` is a ticket the agent marked unread. Unique per tenant, agent
  and ticket.
  """
  use Ecto.Schema

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}ticket_reads" do
    field :tenant_id, :string, default: ""
    field :ticket_id, :id
    field :user_id, :string
    field :last_read_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
