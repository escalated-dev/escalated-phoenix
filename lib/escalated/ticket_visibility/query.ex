defmodule Escalated.TicketVisibility.Query do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.{DepartmentAgent, Ticket}
  alias Escalated.{Tenancy, TicketAccess, TicketVisibility}
  alias Escalated.Tenancy.Tables

  @bindings for index <- 0..64, do: String.to_atom("escalated_access_#{index}")

  def scope(queryable) do
    query = Ecto.Queryable.to_query(queryable)
    if TicketVisibility.restricted?(), do: scope_bindings(query), else: query
  end

  defp scope_bindings(query) do
    if query.combinations != [] or query.with_ctes != nil or length(query.joins) > 64 or
         query.prefix != nil or query.from.prefix != nil,
       do: TicketVisibility.deny!()

    reject_subqueries!(query)

    Enum.reduce(0..length(query.joins), query, fn index, acc ->
      entry = entry!(source!(query, index))
      name = Enum.at(@bindings, index)
      acc = %{acc | aliases: Map.put(acc.aliases, name, index)}
      apply_entry(acc, entry, name)
    end)
  end

  defp apply_entry(query, entry, :parent) do
    query =
      if Tenancy.enabled?(),
        do: where(query, [row], row.tenant_id == ^Tenancy.current_id!()),
        else: query

    apply_entry(
      %{query | aliases: Map.put(query.aliases, :access_parent, 0)},
      entry,
      :access_parent
    )
  end

  defp apply_entry(query, %{name: "tickets"}, name) do
    user = TicketVisibility.actor().user
    query |> departments(TicketAccess.user_id(user), name) |> account(user, name)
  end

  defp apply_entry(query, entry, name) do
    query =
      Enum.reduce(ticket_refs(entry), query, fn {key, {table, parent_key}}, acc ->
        parent = entry!(Escalated.table_name(table))
        permitted = parent.schema |> Ecto.Queryable.to_query() |> apply_entry(parent, :parent)
        permitted = select(permitted, [p], field(p, ^parent_key))
        # Optional parents must all be visible when present. Attachments have a
        # ticket FK in addition to the optional reply FK.
        where(
          acc,
          [{^name, row}],
          is_nil(field(row, ^key)) or field(row, ^key) in subquery(permitted)
        )
      end)

    polymorphic(query, entry, name)
  end

  defp polymorphic(query, entry, name) do
    Enum.reduce(Map.get(entry, :polymorphic_refs, %{}), query, fn {id_key, type_key}, acc ->
      Enum.reduce([entry!(Ticket), entry!(Escalated.Schemas.Reply)], acc, fn parent, scoped ->
        short = parent.schema |> Module.split() |> List.last()
        types = [parent.name, short, Macro.underscore(short), Atom.to_string(parent.schema)]
        permitted = parent.schema |> Ecto.Queryable.to_query() |> apply_entry(parent, :parent)
        permitted = select(permitted, [p], type(p.id, :string))

        where(
          scoped,
          [{^name, row}],
          is_nil(field(row, ^type_key)) or
            field(row, ^type_key) not in ^types or
            type(field(row, ^id_key), :string) in subquery(permitted)
        )
      end)
    end)
  end

  defp departments(query, id, name) do
    if TicketVisibility.department?() do
      members = from(m in DepartmentAgent, where: m.agent_id == ^id, select: m.department_id)
      members = exact_agent(members, id)

      members =
        if Tenancy.enabled?(),
          do: where(members, [m], m.tenant_id == ^Tenancy.current_id!()),
          else: members

      where(query, [{^name, t}], t.department_id in subquery(members))
    else
      query
    end
  end

  defp exact_agent(query, id) do
    if DepartmentAgent.__schema__(:type, :agent_id) == :string and
         Escalated.storage_repo().__adapter__() == Ecto.Adapters.MyXQL do
      where(query, [m], fragment("CAST(? AS BINARY) = CAST(? AS BINARY)", m.agent_id, ^id))
    else
      query
    end
  end

  defp account(query, user, name) do
    if TicketVisibility.account_scope?() do
      case TicketVisibility.resolve_account(
             :agent,
             to_string(Escalated.config(:user_schema)),
             TicketAccess.user_id(user)
           ) do
        %{type: type, id: id} -> exact_account(query, type, id, name)
        nil -> where(query, false)
      end
    else
      query
    end
  end

  def exact_account(query, type, id) do
    query = Ecto.Queryable.to_query(query)
    query = %{query | aliases: Map.put(query.aliases, :account_filter, 0)}
    exact_account(query, type, id, :account_filter)
  end

  defp exact_account(query, type, id, name) do
    # Column collations are binary, and length excludes MySQL PAD SPACE aliases.
    where(
      query,
      [{^name, t}],
      t.account_type == ^type and t.account_id == ^id and
        fragment("length(?)", t.account_type) == ^identity_length(type) and
        fragment("length(?)", t.account_id) == ^identity_length(id)
    )
  end

  defp identity_length(value),
    do:
      if(Escalated.storage_repo().__adapter__() == Ecto.Adapters.MyXQL,
        do: byte_size(value),
        else: String.length(value)
      )

  def ticket_refs(entry),
    do: Enum.filter(entry.local_refs, fn {_, {parent, _}} -> reaches_ticket?(parent, []) end)

  defp reaches_ticket?("tickets", _), do: true

  defp reaches_ticket?(table, seen) do
    if table in seen do
      false
    else
      entry = entry!(Escalated.table_name(table))

      Enum.any?(entry.local_refs, fn {_, {parent, _}} ->
        reaches_ticket?(parent, [table | seen])
      end)
    end
  end

  def entry!(schema) when is_atom(schema),
    do: Enum.find(Tables.entries(), &(&1.schema == schema)) || TicketVisibility.deny!()

  def entry!(table) when is_binary(table),
    do:
      Enum.find(Tables.entries(), &(Escalated.table_name(&1.name) == table)) ||
        TicketVisibility.deny!()

  defp source!(query, 0), do: source(query.from.source)

  defp source!(query, index) do
    join = Enum.at(query.joins, index - 1)

    if join.prefix != nil or join.assoc != nil or join.qual not in [:inner, :cross],
      do: TicketVisibility.deny!()

    source(join.source)
  end

  defp source({table, schema}) do
    entry = entry!(schema || table)
    if table != Escalated.table_name(entry.name), do: TicketVisibility.deny!()
    schema || table
  end

  defp source(_), do: TicketVisibility.deny!()
  defp reject_subqueries!(%Ecto.SubQuery{}), do: TicketVisibility.deny!()

  defp reject_subqueries!(value) when is_map(value),
    do: value |> Map.values() |> Enum.each(&reject_subqueries!/1)

  defp reject_subqueries!(value) when is_list(value), do: Enum.each(value, &reject_subqueries!/1)

  defp reject_subqueries!(value) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.each(&reject_subqueries!/1)

  defp reject_subqueries!(_), do: :ok
end
