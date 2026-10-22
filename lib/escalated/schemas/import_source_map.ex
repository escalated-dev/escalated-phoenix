defmodule Escalated.Schemas.ImportSourceMap do
  @moduledoc """
  Which Escalated record a source record became, per import job. A record
  already mapped is skipped, which is what makes an import resumable; later
  entity types resolve their references (a reply's ticket) through it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}import_source_maps" do
    field :tenant_id, :string, default: ""
    field :import_job_id, :string
    field :entity_type, :string
    field :source_id, :string
    field :escalated_id, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(map, attrs) do
    map
    |> cast(attrs, [:import_job_id, :entity_type, :source_id, :escalated_id])
    |> validate_required([:import_job_id, :entity_type, :source_id, :escalated_id])
  end
end
