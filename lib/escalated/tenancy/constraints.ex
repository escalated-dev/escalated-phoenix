defmodule Escalated.Tenancy.Constraints do
  @moduledoc false

  # SQLite reports a synthesized name from the violating columns even when the
  # actual unique index has an explicit legacy name. Keep the existing schema
  # declarations for PostgreSQL/MySQL and also accept SQLite's tenant name.
  def add_unique_constraints(%Ecto.Changeset{data: %{__struct__: schema}} = changeset) do
    entry = Enum.find(Escalated.Tenancy.Tables.entries(), &(&1.schema == schema))

    Enum.reduce(entry.unique_keys, changeset, fn [first | _] = fields, acc ->
      Ecto.Changeset.unique_constraint(acc, [:tenant_id | fields], error_key: first)
    end)
  end
end
