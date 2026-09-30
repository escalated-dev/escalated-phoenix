defmodule Escalated.Tenancy.PublicUrl do
  @moduledoc """
  Resolves the trusted public origin and mount path for the current merchant.

  In tenant mode the host resolver must implement `public_url(tenant_id)`,
  returning an absolute HTTPS base URL including the package's mount prefix
  (for example `https://merchant.example/support`). Request headers and the
  platform-wide `app_url` are never fallback sources in tenant mode.
  """

  alias Escalated.Tenancy

  def base do
    if Tenancy.enabled?() do
      tenant = Tenancy.current_id!()
      resolver = Escalated.config(:tenant_resolver)

      unless is_atom(resolver) and not is_nil(resolver) and Code.ensure_loaded?(resolver) and
               function_exported?(resolver, :public_url, 1),
             do: invalid!()

      resolver.public_url(tenant) |> validate!()
    else
      Escalated.config(:app_url, "http://localhost") |> String.trim_trailing("/")
    end
  end

  defp validate!(url) when is_binary(url) do
    unless byte_size(url) in 1..4096 and String.valid?(url) and
             not Regex.match?(~r/[\x00-\x20\x7f\\<>"`]/u, url),
           do: invalid!()

    case URI.new(url) do
      {:ok,
       %URI{scheme: "https", host: host, port: port, userinfo: nil, query: nil, fragment: nil}}
      when is_binary(host) and host != "" and port in 1..65_535 ->
        String.trim_trailing(url, "/")

      _ ->
        invalid!()
    end
  end

  defp validate!(_), do: invalid!()

  defp invalid!,
    do:
      raise(Tenancy.Error, message: "tenant_resolver.public_url/1 must return an HTTPS base URL")
end
