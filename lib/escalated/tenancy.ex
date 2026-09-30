defmodule Escalated.Tenancy do
  @moduledoc """
  Trusted tenant context for HTTP requests, jobs and direct service calls.

  Enable with `tenancy_enabled: true` and a `tenant_resolver` module implementing
  `resolve(conn)`, `member?(user, tenant_id)`, `reference?(kind, id, tenant_id)`
  and `scope_users(query, tenant_id)`. Resolve from trusted host routing/session
  state, never an unchecked request parameter. Membership is independent of an
  agent/admin role. Call `run/2` at every asynchronous job entry point.

  The empty namespace belongs only to existing, single-tenant installations.
  Enabling tenancy never adopts those rows automatically.
  """
  @key {__MODULE__, :tenant}

  defmodule Error do
    defexception message: "Escalated tenant access denied", plug_status: 403
  end

  def enabled? do
    case Escalated.config(:tenancy_enabled, false) do
      true -> true
      false -> false
      _ -> raise ArgumentError, "Escalated :tenancy_enabled must be a boolean"
    end
  end

  def current_id! do
    if enabled?(), do: validate_id!(Process.get(@key)), else: ""
  end

  def run(id, fun) when is_function(fun, 0) do
    id = validate_id!(id)
    previous = Process.get(@key)
    Process.put(@key, id)

    try do
      fun.()
    after
      if is_nil(previous), do: Process.delete(@key), else: Process.put(@key, previous)
    end
  end

  def capture(fun) when is_function(fun, 0) do
    if enabled?() do
      id = current_id!()
      fn -> run(id, fun) end
    else
      fun
    end
  end

  def put!(id), do: Process.put(@key, validate_id!(id))
  def clear, do: Process.delete(@key)

  def validate_id!(id) when is_binary(id) do
    if byte_size(id) in 1..128 and String.valid?(id) and String.trim(id) == id and
         not String.contains?(id, <<0>>) do
      id
    else
      deny!()
    end
  end

  def validate_id!(_), do: deny!()

  def resolve(conn), do: invoke(:resolve, [conn], nil)

  def member?(user) do
    not enabled?() or
      (not is_nil(user) and invoke(:member?, [user, current_id!()], false) == true)
  rescue
    Error -> false
  end

  def reference?(kind, id) do
    not enabled?() or is_nil(id) or
      invoke(:reference?, [kind, id, current_id!()], false) == true
  end

  def scope_users(query) do
    case invoke(:scope_users, [query, current_id!()], nil) do
      %Ecto.Query{} = scoped -> scoped
      _ -> deny!()
    end
  end

  def assert_record!(%{tenant_id: id} = record) do
    if enabled?() and id != current_id!(), do: deny!()
    record
  end

  def assert_record!(_), do: deny!()

  def scoped_repo(repo), do: if(enabled?(), do: Escalated.Tenancy.Repo, else: repo)

  def topic(topic) do
    if enabled?() do
      digest = :crypto.hash(:sha256, current_id!()) |> Base.url_encode64(padding: false)
      "escalated:tenant:#{digest}:" <> String.replace_prefix(topic, "escalated:", "")
    else
      topic
    end
  end

  def deny!, do: raise(Error)

  defp invoke(function, args, default) do
    resolver = Escalated.config(:tenant_resolver)

    if is_atom(resolver) and not is_nil(resolver) and Code.ensure_loaded?(resolver) and
         function_exported?(resolver, function, length(args)) do
      apply(resolver, function, args)
    else
      default
    end
  end
end
