defmodule Escalated.Tenancy.Backfill do
  @moduledoc """
  Explicit migration of one legacy installation into one empty tenant.

  `preview/1` only reads. `apply/2` requires `writers_stopped: true`; stop HTTP,
  workers and inbound integrations first. All registered tenant tables move in
  one transaction. The host resolver must already authorize every referenced
  host identity/entity for the destination tenant. A tenant is never inferred
  from an email address or a ticket requester.
  """
  import Ecto.Query
  alias Escalated.Tenancy
  alias Escalated.Tenancy.{Tables, Writes}

  def preview(tenant) do
    Tenancy.run(tenant, fn ->
      if not Tenancy.enabled?(), do: Tenancy.deny!()
      report()
    end)
  end

  def apply(tenant, opts \\ []) do
    if opts[:writers_stopped] != true,
      do: raise(ArgumentError, "Stop all writers before applying a legacy backfill")

    Tenancy.run(tenant, fn ->
      if not Tenancy.enabled?(), do: Tenancy.deny!()

      raw().transaction(fn ->
        result = report()
        if result.issues != [], do: raw().rollback({:invalid, result})

        Enum.each(Tables.entries(), fn entry ->
          raw().update_all(legacy(entry), set: [tenant_id: Tenancy.current_id!()])
        end)

        result.counts
      end)
    end)
  end

  defp report do
    entries = Tables.entries()

    counts =
      Map.new(entries, fn entry -> {entry.name, raw().aggregate(legacy(entry), :count)} end)

    occupied =
      for entry <- entries,
          raw().exists?(
            from(row in entry.schema, where: row.tenant_id == ^Tenancy.current_id!())
          ),
          do: %{table: entry.name, reason: :destination_not_empty}

    issues =
      Enum.reduce(entries, occupied, fn entry, issues ->
        # Upgrade is a deliberate offline operation. Keep only bounded diagnostic
        # metadata; never include contact emails, ticket bodies or capability data.
        raw().all(legacy(entry))
        |> Enum.reduce(issues, fn row, acc -> validate_row(entry, row) ++ acc end)
      end)

    %{tenant_id: Tenancy.current_id!(), counts: counts, issues: issues}
  end

  defp validate_row(entry, row) do
    local =
      for {field, {parent, key}} <- entry.local_refs,
          id = Map.get(row, field),
          not is_nil(id),
          not legacy_reference?(parent, key, id),
          do: issue(entry, row, field)

    host =
      for field <- entry.host_refs,
          id = Map.get(row, field),
          not is_nil(id),
          not Tenancy.reference?(:user, id),
          do: issue(entry, row, field)

    lists =
      for field <- Map.get(entry, :host_ref_lists, []),
          id <- Map.get(row, field) || [],
          not Tenancy.reference?(:user, id),
          do: issue(entry, row, field)

    poly =
      for {field, type_field} <- Map.get(entry, :polymorphic_refs, %{}),
          id = Map.get(row, field),
          not is_nil(id),
          not legacy_polymorphic?(Map.get(row, type_field), id),
          do: issue(entry, row, field)

    local ++ host ++ lists ++ poly
  end

  defp legacy_polymorphic?(type, id) do
    case Writes.polymorphic_entry(type) do
      nil ->
        kind =
          if type in [
               nil,
               "user",
               "User",
               "App\\Models\\User",
               to_string(Escalated.config(:user_schema))
             ],
             do: :user,
             else: type

        Tenancy.reference?(kind, id)

      entry ->
        legacy_reference?(entry.name, :id, id)
    end
  end

  defp legacy_reference?(name, key, id) do
    table = Escalated.table_name(name)

    raw().exists?(
      from(row in table, where: field(row, :tenant_id) == "" and field(row, ^key) == ^id)
    )
  end

  defp issue(entry, row, field),
    do: %{table: entry.name, id: Map.get(row, :id), field: field, reason: :foreign_reference}

  defp legacy(entry), do: from(row in entry.schema, where: row.tenant_id == "")
  defp raw, do: Escalated.storage_repo()
end
