defmodule Escalated.Tenancy.Maintenance do
  @moduledoc """
  Runs a maintenance operation in explicitly selected merchant contexts.

  With tenancy enabled, `--tenant ID` selects one tenant. Otherwise the trusted
  `tenant_resolver.tenants/0` callback must return the complete list of IDs to
  process. Every ID is validated before any operation starts. No tenant is
  discovered from package data and the legacy empty namespace is never included.

  The callback receives the remaining command arguments unchanged. Exceptions
  stop the sweep and `Tenancy.run/2` restores the caller's context. Schedulers
  may call `run([], fn _args -> work() end)` using the same trusted catalog.
  """

  alias Escalated.Tenancy

  def run(args, callback) when is_list(args) and is_function(callback, 1) do
    {selected, remaining} = extract_tenant(args, nil, [])

    if Tenancy.enabled?() do
      tenants = if selected, do: [selected], else: catalog!()
      tenants = tenants |> Enum.map(&Tenancy.validate_id!/1) |> Enum.uniq()

      Enum.map(tenants, fn tenant ->
        {tenant, Tenancy.run(tenant, fn -> callback.(remaining) end)}
      end)
    else
      if selected, do: raise(ArgumentError, "--tenant requires tenancy_enabled: true")
      [{"", callback.(remaining)}]
    end
  end

  defp catalog! do
    resolver = Escalated.config(:tenant_resolver)

    unless is_atom(resolver) and not is_nil(resolver) and Code.ensure_loaded?(resolver) and
             function_exported?(resolver, :tenants, 0) do
      raise Tenancy.Error,
        message:
          "Maintenance requires --tenant ID or the trusted tenant_resolver.tenants/0 catalog"
    end

    case resolver.tenants() do
      tenants when is_list(tenants) ->
        tenants

      _ ->
        raise Tenancy.Error, message: "tenant_resolver.tenants/0 must return a list of tenant IDs"
    end
  end

  defp extract_tenant([], selected, remaining), do: {selected, Enum.reverse(remaining)}

  defp extract_tenant(["--" | rest], selected, remaining),
    do: {selected, Enum.reverse(remaining) ++ ["--" | rest]}

  defp extract_tenant(["--tenant", id | rest], nil, remaining) do
    if String.starts_with?(id, "--"), do: raise(ArgumentError, "--tenant requires one tenant ID")
    extract_tenant(rest, Tenancy.validate_id!(id), remaining)
  end

  defp extract_tenant(["--tenant" | _], _selected, _remaining),
    do: raise(ArgumentError, "--tenant requires exactly one tenant ID")

  defp extract_tenant(["--tenant=" <> id | rest], nil, remaining),
    do: extract_tenant(rest, Tenancy.validate_id!(id), remaining)

  defp extract_tenant(["--tenant=" <> _ | _], _selected, _remaining),
    do: raise(ArgumentError, "--tenant may only be supplied once")

  defp extract_tenant([arg | rest], selected, remaining),
    do: extract_tenant(rest, selected, [arg | remaining])
end
