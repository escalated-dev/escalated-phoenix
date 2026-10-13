defmodule Escalated.TicketVisibility do
  @moduledoc "Opt-in, process-local ticket access. Use with_user/2 at host job boundaries."
  import Ecto.Query
  alias Escalated.{Permissions, TicketAccess}
  alias Escalated.Schemas.Ticket

  @key {__MODULE__, :actor}

  defmodule Error do
    defexception message: "Ticket access denied", plug_status: 403
  end

  def enabled?, do: department?() or account_scope?()
  def department?, do: Escalated.config(:visibility, :all) in [:department, "department"]
  def accounts?, do: account_option(:enabled) == true
  def account_scope?, do: accounts?() and account_option(:scope_agents) == true
  def account_option(key), do: Map.get(Escalated.config(:accounts, %{}), key)
  def actor, do: Process.get(@key)
  def clear, do: Process.delete(@key)
  def restore(nil), do: clear()
  def restore(actor), do: Process.put(@key, actor)

  def put_user(user) do
    clear()
    restricted = enabled?() and Permissions.agent?(user) and not Permissions.admin?(user)
    Process.put(@key, %{user: user, restricted: restricted})
  end

  def restricted?, do: enabled?() and match?(%{restricted: true}, actor())

  def with_user(user, fun) when is_function(fun, 0) do
    previous = actor()

    try do
      put_user(user)
      fun.()
    after
      restore(previous)
    end
  end

  def assert_record!(%{__struct__: schema} = record) do
    if restricted?() do
      keys = schema.__schema__(:primary_key)
      filters = Enum.map(keys, &{&1, Map.fetch!(record, &1)})
      if keys == [] or not Escalated.repo().exists?(where(schema, ^filters)), do: deny!()
    end

    record
  end

  def can_view?(%Ticket{} = ticket, user) do
    Escalated.Tenancy.assert_record!(ticket)
    fresh = with_user(nil, fn -> Escalated.repo().get(Ticket, ticket.id) end)

    with_user(user, fn ->
      not is_nil(fresh) and
        (Permissions.admin?(user) or
           (Permissions.agent?(user) and not is_nil(Escalated.repo().get(Ticket, ticket.id))) or
           (not Permissions.agent?(user) and TicketAccess.requester?(fresh, user)))
    end)
  end

  def load_user(id) do
    case Escalated.config(:access_user_resolver) do
      fun when is_function(fun, 1) -> fun.(id)
      _ -> Escalated.user_repo().get(Escalated.user_schema(), id)
    end
    |> same_user(id)
  end

  defp same_user(user, id) do
    if not is_nil(user) and to_string(TicketAccess.user_id(user)) == to_string(id), do: user
  end

  def can_assign?(ticket, id) do
    if enabled?() and not is_nil(id) do
      user = load_user(id)
      Permissions.admin?(user) or (Permissions.agent?(user) and matches?(ticket, user))
    else
      true
    end
  end

  def matches?(ticket, user) do
    matches_department?(ticket, user) and matches_account?(ticket, user)
  end

  defp matches_department?(%{department_id: nil}, _user), do: not department?()

  defp matches_department?(ticket, user) do
    if department?() do
      query =
        from(m in Escalated.Schemas.DepartmentAgent,
          where: m.department_id == ^ticket.department_id
        )

      query =
        if Escalated.Tenancy.enabled?(),
          do: where(query, [m], m.tenant_id == ^Escalated.Tenancy.current_id!()),
          else: query

      not is_nil(ticket.department_id) and
        Enum.any?(Escalated.storage_repo().all(query), fn member ->
          to_string(member.agent_id) == to_string(TicketAccess.user_id(user))
        end)
    else
      true
    end
  end

  defp matches_account?(ticket, user) do
    if account_scope?() do
      expected =
        resolve_account(
          :agent,
          to_string(Escalated.config(:user_schema)),
          TicketAccess.user_id(user)
        )

      not is_nil(expected) and
        expected == pair(%{type: ticket.account_type, id: ticket.account_id})
    else
      true
    end
  end

  def recipients(ticket, ids) do
    if enabled?() do
      Enum.filter(Enum.uniq(ids), fn id ->
        user = load_user(id)
        not is_nil(user) and can_view?(ticket, user)
      end)
    else
      Enum.uniq(ids)
    end
  end

  def resolve_account(kind, type, id) do
    if accounts?() do
      case account_option(:resolver) do
        fun when is_function(fun, 3) -> pair(fun.(kind, type, id))
        _ -> nil
      end
    end
  end

  def pair(%{type: type, id: id}), do: pair(%{"type" => type, "id" => id})

  def pair(%{"type" => type, "id" => id})
      when is_binary(type) and (is_binary(id) or is_integer(id)) do
    id = to_string(id)
    if byte_size(type) in 1..191 and byte_size(id) in 1..191, do: %{type: type, id: id}
  end

  def pair(_), do: nil
  def deny!, do: raise(Error)
end
