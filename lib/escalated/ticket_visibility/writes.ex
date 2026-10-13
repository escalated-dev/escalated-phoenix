defmodule Escalated.TicketVisibility.Writes do
  @moduledoc false
  alias Ecto.Changeset
  alias Escalated.TicketVisibility
  alias Escalated.TicketVisibility.Query

  def prepare(cs, action) do
    if TicketVisibility.enabled?() do
      entry = Query.entry!(cs.data.__struct__)
      if action != :insert, do: TicketVisibility.assert_record!(cs.data)
      values = Changeset.apply_changes(cs)
      if action != :delete, do: validate_parents!(entry, values)

      if action != :delete and Map.has_key?(cs.changes, :assigned_to) do
        if not TicketVisibility.can_assign?(values, values.assigned_to),
          do: TicketVisibility.deny!()
      end

      Enum.reduce(cs.data.__struct__.__schema__(:associations), cs, fn key, current ->
        case Map.fetch(current.changes, key) do
          :error -> current
          {:ok, value} -> %{current | changes: Map.put(current.changes, key, association(value))}
        end
      end)
    else
      cs
    end
  end

  defp association(nil), do: nil
  defp association(list) when is_list(list), do: Enum.map(list, &association/1)

  defp association(value) do
    cs = Changeset.change(value)
    action = if cs.data.__meta__.state == :built, do: :insert, else: :update
    prepare(cs, action)
  end

  defp validate_parents!(entry, values) do
    if TicketVisibility.restricted?() do
      Enum.each(Query.ticket_refs(entry), fn {key, {parent, _}} ->
        assert_parent!(parent, Map.get(values, key))
      end)

      Enum.each(Map.get(entry, :polymorphic_refs, %{}), fn {id_key, type_key} ->
        parent = Escalated.Tenancy.Writes.polymorphic_entry(Map.get(values, type_key))

        if parent && Map.get(values, id_key) &&
             is_nil(Escalated.repo().get(parent.schema, Map.get(values, id_key))),
           do: TicketVisibility.deny!()
      end)
    end
  end

  defp assert_parent!(_parent, nil), do: :ok

  defp assert_parent!(parent, id) do
    schema = Query.entry!(Escalated.table_name(parent)).schema
    if is_nil(Escalated.repo().get(schema, id)), do: TicketVisibility.deny!()
  end

  def rows!(source, rows) do
    if TicketVisibility.enabled?() do
      entry = Query.entry!(source)

      Enum.each(rows, fn row ->
        values = Map.new(row)
        if Map.has_key?(values, :assigned_to), do: TicketVisibility.deny!()
        validate_parents!(entry, values)
      end)
    end

    rows
  end

  def validate_bulk!(queryable, updates) do
    if TicketVisibility.enabled?() do
      query = Ecto.Queryable.to_query(queryable)
      {table, schema} = query.from.source
      entry = Query.entry!(schema || table)

      protected =
        [:id, :assigned_to, :agent_id] ++
          Map.keys(entry.local_refs) ++
          Map.keys(Map.get(entry, :polymorphic_refs, %{})) ++
          Map.values(Map.get(entry, :polymorphic_refs, %{}))

      if query.updates != [] or
           Enum.any?(updates, &protected_update?(&1, protected)),
         do: TicketVisibility.deny!()
    end
  end

  defp protected_update?({_, fields}, protected),
    do: Enum.any?(fields, fn {key, _} -> key in protected end)

  def options!(opts) do
    if TicketVisibility.enabled?() and
         Keyword.get(opts, :on_conflict, :raise) not in [:raise, :nothing],
       do: TicketVisibility.deny!()
  end
end
