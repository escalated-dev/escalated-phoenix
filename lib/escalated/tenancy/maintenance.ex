defmodule Escalated.Tenancy.Maintenance do
  @moduledoc """
  Runs a maintenance operation in explicitly selected merchant contexts.

  With tenancy enabled, `--tenant ID` selects one tenant. Otherwise the trusted
  `tenant_resolver.tenants/0` callback must return the complete list of IDs to
  process. Every ID is validated before any operation starts. No tenant is
  discovered from package data and the legacy empty namespace is never included.

  The callback receives the remaining command arguments unchanged. A tenant
  whose callback raises (or exits or throws) is logged by tenant ID and error
  type only, and the sweep continues with the next tenant, so one merchant's
  bad data cannot stop maintenance for the others. `Tenancy.run/2` restores the
  caller's context after each tenant. Once every tenant has run, any failure is
  raised as `Escalated.Tenancy.Maintenance.Error`, whose `failures` field lists
  each failed tenant with what it raised, so mix tasks and schedulers still
  exit non-zero. Schedulers may call `run([], fn _args -> work() end)` using the
  same trusted catalog.
  """

  alias Escalated.Tenancy
  require Logger

  defmodule Error do
    @moduledoc "Raised after a sweep in which at least one tenant failed."
    defexception failures: [], message: "Escalated maintenance failed"

    @impl true
    def exception(failures) do
      tenants = Enum.map_join(failures, ", ", &elem(&1, 0))

      %__MODULE__{
        failures: failures,
        message: "Escalated maintenance failed for #{length(failures)} tenant(s): #{tenants}"
      }
    end
  end

  def run(args, callback) when is_list(args) and is_function(callback, 1) do
    {selected, remaining} = extract_tenant(args, nil, [])

    if Tenancy.enabled?() do
      tenants = if selected, do: [selected], else: catalog!()
      tenants = tenants |> Enum.map(&Tenancy.validate_id!/1) |> Enum.uniq()

      results = Enum.map(tenants, &run_tenant(&1, callback, remaining))

      case for {tenant, {:failed, error}} <- results, do: {tenant, error} do
        [] -> Enum.map(results, fn {tenant, {:ok, result}} -> {tenant, result} end)
        failures -> raise Error, failures
      end
    else
      if selected, do: raise(ArgumentError, "--tenant requires tenancy_enabled: true")
      [{"", callback.(remaining)}]
    end
  end

  defp run_tenant(tenant, callback, remaining) do
    {tenant, {:ok, Tenancy.run(tenant, fn -> callback.(remaining) end)}}
  catch
    kind, reason ->
      error = Exception.normalize(kind, reason, __STACKTRACE__)

      # Only the tenant and the error type: messages can carry row data.
      Logger.error(
        "Escalated maintenance failed for tenant #{tenant}: #{kind} #{describe(error)}"
      )

      {tenant, {:failed, error}}
  end

  defp describe(%{__exception__: true, __struct__: module}), do: inspect(module)
  defp describe(_), do: "(non-exception)"

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
