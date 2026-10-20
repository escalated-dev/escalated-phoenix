defmodule Escalated.OutboundUrlGuard do
  @moduledoc """
  Decides whether the package may send a request to a URL someone typed into
  the admin UI, such as a webhook endpoint. Mirrors Laravel's
  `Escalated\\Laravel\\Support\\OutboundUrlGuard`.

  The URL must be `http` or `https`, and every address its host resolves to
  must be public. Loopback, private, carrier-grade NAT, link-local (cloud
  metadata sits at 169.254.169.254), multicast, documentation and other
  reserved ranges are refused, IPv4-mapped and NAT64 IPv6 addresses are judged
  by the IPv4 address they carry, and a host that does not resolve at all is
  refused too.

  Host names are resolved with `:inet.getaddrs/2`. A host app (or a test) can
  replace that with `config :escalated, :outbound_url_resolver, fun`, where
  `fun.(host)` returns a list of IP address strings or tuples.
  """

  import Bitwise

  @refusal "Not sent: the URL must use http or https and resolve to a public address."

  @doc "The message recorded when a request is refused."
  def refusal_message, do: @refusal

  @doc "True when a request to `url` may be sent."
  @spec allows?(String.t() | nil, keyword()) :: boolean()
  def allows?(url, opts \\ []), do: match?({:ok, _}, public_address_for(url, opts))

  @doc """
  The public address a request to `url` should connect to, as an `:inet`
  address tuple, or `:error` when the URL must not be requested.

  Options:

    * `:resolver` - `fun.(host)` returning a list of addresses, in place of
      the configured or default resolver.
  """
  @spec public_address_for(String.t() | nil, keyword()) :: {:ok, :inet.ip_address()} | :error
  def public_address_for(url, opts \\ [])

  def public_address_for(url, opts) when is_binary(url) do
    with {:ok, %URI{scheme: scheme, host: host}} <- URI.new(String.trim(url)),
         true <- is_binary(scheme) and String.downcase(scheme) in ["http", "https"],
         host when is_binary(host) and host != "" <- host,
         [_ | _] = addresses <- resolve(host, opts),
         true <- Enum.all?(addresses, &public?/1) do
      {:ok, hd(addresses)}
    else
      _ -> :error
    end
  end

  def public_address_for(_url, _opts), do: :error

  @doc """
  Every address `host` resolves to, as `:inet` tuples. An IP literal resolves
  to itself; anything a custom resolver returns that is not an IP is dropped.
  """
  @spec resolve(String.t(), keyword()) :: [:inet.ip_address()]
  def resolve(host, opts \\ []) do
    host = host |> String.trim_leading("[") |> String.trim_trailing("]")

    case parse_ip(host) do
      {:ok, ip} ->
        [ip]

      :error ->
        resolver = Keyword.get(opts, :resolver) || Escalated.config(:outbound_url_resolver)

        if is_function(resolver, 1) do
          host |> resolver.() |> List.wrap() |> Enum.flat_map(&to_ip/1)
        else
          default_resolve(host)
        end
    end
  end

  defp default_resolve(host) do
    name = String.to_charlist(host)

    Enum.flat_map([:inet, :inet6], fn family ->
      case :inet.getaddrs(name, family) do
        {:ok, addresses} -> addresses
        {:error, _} -> []
      end
    end)
    |> Enum.uniq()
  end

  defp to_ip(ip) when is_tuple(ip) and tuple_size(ip) in [4, 8], do: [ip]

  defp to_ip(ip) when is_binary(ip) do
    case parse_ip(ip) do
      {:ok, parsed} -> [parsed]
      :error -> []
    end
  end

  defp to_ip(_), do: []

  defp parse_ip(value) do
    case :inet.parse_strict_address(String.to_charlist(value)) do
      {:ok, ip} -> {:ok, ip}
      {:error, _} -> :error
    end
  end

  # Ranges that are not globally routable (RFC 6890 and the IANA special-purpose
  # registries), as {network, prefix length}.
  @blocked_v4 [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 88, 99, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @blocked_v6 [
    # Unspecified, loopback and the deprecated IPv4-compatible block.
    {{0, 0, 0, 0, 0, 0, 0, 0}, 96},
    {{0x100, 0, 0, 0, 0, 0, 0, 0}, 64},
    {{0x2001, 0, 0, 0, 0, 0, 0, 0}, 23},
    {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32},
    {{0x2002, 0, 0, 0, 0, 0, 0, 0}, 16},
    {{0xFC00, 0, 0, 0, 0, 0, 0, 0}, 7},
    {{0xFE80, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFEC0, 0, 0, 0, 0, 0, 0, 0}, 10},
    {{0xFF00, 0, 0, 0, 0, 0, 0, 0}, 8}
  ]

  @doc "True when `ip` (an `:inet` tuple or string) is a public, globally routable address."
  @spec public?(:inet.ip_address() | String.t()) :: boolean()
  def public?(ip) when is_binary(ip) do
    case parse_ip(ip) do
      {:ok, parsed} -> public?(parsed)
      :error -> false
    end
  end

  def public?({_, _, _, _} = ip), do: not Enum.any?(@blocked_v4, &in_range?(ip, &1, 8))

  # IPv4-mapped (::ffff:a.b.c.d) and NAT64 (64:ff9b::a.b.c.d) addresses reach
  # the IPv4 address they carry.
  def public?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: public?(v4(hi, lo))
  def public?({0x64, 0xFF9B, 0, 0, 0, 0, hi, lo}), do: public?(v4(hi, lo))

  def public?({_, _, _, _, _, _, _, _} = ip),
    do: not Enum.any?(@blocked_v6, &in_range?(ip, &1, 16))

  def public?(_), do: false

  defp v4(hi, lo), do: {hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF}

  defp in_range?(ip, {network, prefix}, width) do
    bits = tuple_size(ip) * width
    shift = bits - prefix
    to_int(ip, width) >>> shift == to_int(network, width) >>> shift
  end

  defp to_int(ip, width) do
    ip |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> (acc <<< width) + part end)
  end
end
