defmodule Escalated.Schemas.TicketTag do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}ticket_tags" do
    field :tenant_id, :string, default: ""
    belongs_to :ticket, Escalated.Schemas.Ticket
    belongs_to :tag, Escalated.Schemas.Tag
  end

  @doc false
  def tenant_defaults(schema, _owner) do
    struct(schema, tenant_id: Escalated.Tenancy.current_id!())
  end
end
