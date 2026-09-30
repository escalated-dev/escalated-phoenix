defmodule Escalated.Schemas.GuestMailboxBudget do
  @moduledoc "Platform-wide mailbox delivery counters. Never tenant-scoped; contain no email addresses."
  use Ecto.Schema
  @primary_key {:mailbox_hash, :string, autogenerate: false}
  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}guest_mailbox_budgets" do
    field :attempts, :integer, default: 0
    field :expires_at, :utc_datetime
  end
end
