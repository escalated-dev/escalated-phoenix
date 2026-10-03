defmodule Escalated.Tenancy.Writes do
  @moduledoc false
  import Ecto.Query
  alias Ecto.Changeset
  alias Escalated.Tenancy
  alias Escalated.Tenancy.{Query, Repo}

  def prepare(record, action) do
    cs = Changeset.change(record)
    entry = Query.entry!(cs.data.__struct__)
    tenant = Tenancy.current_id!()

    if cs.data.__meta__.source != Escalated.table_name(entry.name) or
         cs.data.__meta__.prefix != nil,
       do: Tenancy.deny!()

    if Changeset.get_change(cs, :tenant_id, tenant) != tenant, do: Tenancy.deny!()

    assert_identity!(cs, action, tenant)
    changed = Map.keys(cs.changes)

    cs = Changeset.put_change(cs, :tenant_id, tenant)

    cs =
      if action in [:update, :delete],
        do: %{cs | filters: Map.put(cs.filters, :tenant_id, tenant)},
        else: cs

    # An insert proves every reference it stores. An update proves only the
    # references it writes: a stored one may name a user whose membership has
    # since been revoked, and that must not block unrelated changes to the row
    # (or deactivating the revoked user's own seat). A delete writes nothing.
    # Ownership of the row itself is checked by assert_identity!/3 either way.
    case action do
      :insert -> validate_written!(entry, Changeset.apply_changes(cs), :all)
      :update -> validate_written!(entry, Changeset.apply_changes(cs), changed)
      :delete -> :ok
    end

    Enum.reduce(cs.data.__struct__.__schema__(:associations), cs, fn name, current ->
      case Map.fetch(current.changes, name) do
        :error ->
          current

        {:ok, value} ->
          prepared = prepare_association(value)
          %{current | changes: Map.put(current.changes, name, prepared)}
      end
    end)
  end

  defp assert_identity!(%Changeset{data: %{__meta__: %{state: :built}}} = cs, :insert, tenant) do
    if cs.data.tenant_id not in ["", tenant] or (primary_key?(cs) and not challenge_id?(cs)),
      do: Tenancy.deny!()
  end

  defp assert_identity!(cs, _action, _tenant) do
    Tenancy.assert_record!(cs.data)
    assert_stored!(cs.data)

    if Enum.any?(cs.data.__struct__.__schema__(:primary_key), &Map.has_key?(cs.changes, &1)),
      do: Tenancy.deny!()
  end

  def assert_stored!(record) do
    keys = record.__struct__.__schema__(:primary_key)
    if keys == [], do: Tenancy.deny!()
    filters = Enum.map(keys, &{&1, Map.fetch!(record, &1)})
    if Enum.any?(filters, fn {_, value} -> is_nil(value) end), do: Tenancy.deny!()
    if not Repo.exists?(where(record.__struct__, ^filters)), do: Tenancy.deny!()
  end

  def rows!(source, rows) when is_list(rows) do
    entry = Query.entry!(source)
    tenant = Tenancy.current_id!()

    Enum.map(rows, fn row ->
      row = Map.new(row)
      if Map.get(row, :tenant_id, tenant) != tenant or Map.has_key?(row, :id), do: Tenancy.deny!()
      if Enum.any?(row, fn {_, value} -> sql_value?(value) end), do: Tenancy.deny!()
      row = Map.put(row, :tenant_id, tenant)
      validate_written!(entry, row, :all)
      row
    end)
  end

  def rows!(_, _), do: Tenancy.deny!()

  # insert_all turns these row values into SQL of their own (a subquery, or a
  # value shared through the :placeholders option) that the tenant scope never
  # sees, so only literal values are accepted.
  defp sql_value?(%Ecto.Query{}), do: true
  defp sql_value?(%Ecto.SubQuery{}), do: true
  defp sql_value?({:placeholder, _}), do: true
  defp sql_value?(_), do: false

  defp validate_written!(entry, values, fields) do
    validate_references!(entry, values, fields)

    if written?(fields, :reply_id) or written?(fields, :ticket_id),
      do: validate_pair!(entry.name, values)
  end

  defp written?(:all, _field), do: true
  defp written?(fields, field), do: field in fields

  def validate_references!(entry, values, fields \\ :all) do
    local_refs = Enum.filter(entry.local_refs, fn {field, _} -> written?(fields, field) end)
    host_refs = Enum.filter(entry.host_refs, &written?(fields, &1))
    host_ref_lists = Enum.filter(Map.get(entry, :host_ref_lists, []), &written?(fields, &1))

    # A polymorphic reference is re-checked when either half of the pair changes.
    polymorphic_refs =
      Enum.filter(Map.get(entry, :polymorphic_refs, %{}), fn {id_field, type_field} ->
        written?(fields, id_field) or written?(fields, type_field)
      end)

    Enum.each(local_refs, fn {field, {parent, key}} ->
      if id = Map.get(values, field) do
        table = Escalated.table_name(parent)

        if not Repo.exists?(from(row in table, where: field(row, ^key) == ^id)),
          do: Tenancy.deny!()
      end
    end)

    Enum.each(host_refs, fn field ->
      id = Map.get(values, field)
      if not Tenancy.reference?(:user, id), do: Tenancy.deny!()
      if field in [:assigned_to, :agent_id] and not is_nil(id), do: assert_agent!(id)
    end)

    Enum.each(host_ref_lists, fn field ->
      Enum.each(Map.get(values, field) || [], fn id ->
        if not Tenancy.reference?(:user, id), do: Tenancy.deny!()
        assert_agent!(id)
      end)
    end)

    Enum.each(polymorphic_refs, fn {id_field, type_field} ->
      if id = Map.get(values, id_field) do
        validate_polymorphic!(Map.get(values, type_field), id)
      end
    end)
  end

  defp assert_agent!(id) do
    user = Escalated.user_repo().get(Escalated.user_schema(), id)
    if not Escalated.Permissions.agent?(user), do: Tenancy.deny!()
  end

  def validate_bulk!(queryable, updates) do
    query = Ecto.Queryable.to_query(queryable)
    {name, schema} = query.from.source
    entry = Query.entry!(schema || name)
    protected = protected_fields(entry)

    # SQL expressions changing ownership/reference columns cannot be checked
    # row-by-row. Call update/2 on an owned record for those changes.
    if query.updates != [], do: Tenancy.deny!()

    Enum.each(updates, fn {operation, fields} ->
      if operation not in [:set, :inc, :push, :pull], do: Tenancy.deny!()
      if Enum.any?(fields, fn {field, _} -> field in protected end), do: Tenancy.deny!()
    end)
  end

  def options!(source, opts) do
    if Keyword.has_key?(opts, :prefix), do: Tenancy.deny!()
    entry = Query.entry!(source)

    if entry.schema == Escalated.Schemas.GuestChallenge and
         Keyword.get(opts, :on_conflict, :raise) != :raise,
       do: Tenancy.deny!()

    case Keyword.get(opts, :on_conflict, :raise) do
      value when value in [:raise, :nothing] ->
        add_conflict_tenant(opts)

      {:replace, fields} ->
        target = Keyword.get(opts, :conflict_target, []) |> List.delete(:tenant_id)

        valid_target =
          target in entry.unique_keys or
            (target == [] and entry.unique_keys != [] and
               Repo.__adapter__() == Ecto.Adapters.MyXQL)

        if not valid_target or Enum.any?(fields, &(&1 in protected_fields(entry))),
          do: Tenancy.deny!()

        add_conflict_tenant(opts)

      _ ->
        Tenancy.deny!()
    end
  end

  defp add_conflict_tenant(opts) do
    case Keyword.get(opts, :conflict_target) do
      fields when is_list(fields) ->
        Keyword.put(opts, :conflict_target, Enum.uniq([:tenant_id | fields]))

      nil ->
        opts

      _ ->
        Tenancy.deny!()
    end
  end

  defp protected_fields(entry) do
    [:id, :tenant_id] ++
      Map.keys(entry.local_refs) ++
      entry.host_refs ++
      Map.get(entry, :host_ref_lists, []) ++
      Map.keys(Map.get(entry, :polymorphic_refs, %{})) ++
      Map.values(Map.get(entry, :polymorphic_refs, %{}))
  end

  defp primary_key?(cs) do
    Enum.any?(
      cs.data.__struct__.__schema__(:primary_key),
      &(not is_nil(Changeset.get_field(cs, &1)))
    )
  end

  defp challenge_id?(%Changeset{data: %{__struct__: Escalated.Schemas.GuestChallenge}} = cs),
    do: match?({:ok, _}, Ecto.UUID.cast(Changeset.get_field(cs, :id)))

  defp challenge_id?(_), do: false

  defp prepare_association(nil), do: nil

  defp prepare_association(values) when is_list(values),
    do: Enum.map(values, &prepare_association/1)

  defp prepare_association(%Changeset{data: %{__meta__: %{state: :built}}} = cs),
    do: prepare(cs, :insert)

  defp prepare_association(%Changeset{} = cs), do: prepare(cs, :update)
  defp prepare_association(record), do: prepare_association(Changeset.change(record))

  defp validate_polymorphic!(type, id) do
    # Host polymorphic kinds are explicit host policy decisions. Built-in
    # package records are checked on Escalated's connection, never users'.
    entry = polymorphic_entry(type)

    cond do
      entry ->
        if is_nil(Repo.get(entry.schema, id)), do: Tenancy.deny!()

      type in [
        nil,
        "user",
        "User",
        "App\\Models\\User",
        to_string(Escalated.config(:user_schema))
      ] ->
        if not Tenancy.reference?(:user, id), do: Tenancy.deny!()

      true ->
        if not Tenancy.reference?(type, id), do: Tenancy.deny!()
    end
  end

  def polymorphic_entry(type) do
    Enum.find(Escalated.Tenancy.Tables.entries(), fn e ->
      short = e.schema |> Module.split() |> List.last()
      type in [e.name, short, Macro.underscore(short), Atom.to_string(e.schema)]
    end)
  end

  defp validate_pair!("attachments", %{reply_id: id, ticket_id: ticket_id}) when not is_nil(id) do
    reply = Repo.get(Escalated.Schemas.Reply, id)
    if is_nil(reply) or reply.ticket_id != ticket_id, do: Tenancy.deny!()
  end

  defp validate_pair!(_, _), do: :ok
end
