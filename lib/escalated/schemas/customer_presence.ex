defmodule Escalated.Schemas.CustomerPresence do
  @moduledoc """
  When a customer was last seen on the customer portal or the widget (ADR
  2026-11-05-agent-panel-data). The subject is a host user (`user`), a
  contact (`contact`), or a guest ticket itself (`ticket`). Only agent pages
  ever read it.
  """
  use Ecto.Schema

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}customer_presence" do
    field :tenant_id, :string, default: ""
    field :subject_type, :string
    field :subject_id, :string
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end
end
