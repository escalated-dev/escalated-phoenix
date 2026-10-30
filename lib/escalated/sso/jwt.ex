defmodule Escalated.Sso.Jwt do
  @moduledoc """
  The JWT hand-off provider (ADR 2026-10-29-configurable-access-features).
  The identity provider sends the user back to `{prefix}/sso/jwt/callback`
  with a `jwt` parameter.

  Signatures are checked by `joken` (on `jose`) with the algorithm pinned to
  the configured `sso_jwt_algorithm`: HS256/384/512 with `sso_jwt_secret`,
  RS256/384/512 with the PEM public key in the same field. A token naming any
  other algorithm, `none` included, is refused by the library. Then:

  - `exp` is required and must not have passed (with `clock_skew`);
  - `nbf` and `iat`, when present, must not be in the future;
  - `aud` must name `Escalated.Sso.jwt_audience/1`;
  - `jti` is required and works once (`Escalated.Sso.MessageIds`).
  """
  alias Escalated.Sso
  alias Escalated.Sso.{Identity, MessageIds}

  @algorithms ~w(HS256 HS384 HS512 RS256 RS384 RS512)

  @doc "The algorithms an admin may choose."
  def algorithms, do: @algorithms

  @doc """
  Validates `token` against the stored settings. Returns `{:ok, identity}` or
  `{:error, reason}`, where `reason` is for the log, never for the user.
  """
  def validate(token, settings, audience) do
    algorithm = present(settings["sso_jwt_algorithm"]) || "HS256"
    secret = settings["sso_jwt_secret"] || ""

    with :ok <- check(is_binary(token) and token != "", "no token was sent"),
         :ok <- check(algorithm in @algorithms, "unsupported algorithm #{algorithm}"),
         :ok <- check(secret != "", "no secret or public key is configured"),
         {:ok, signer} <- signer(algorithm, secret),
         {:ok, claims} <- verify(token, signer),
         {:ok, exp} <- expiry(claims),
         :ok <- not_before(claims),
         :ok <- audience(claims, audience),
         {:ok, jti} <- jti(claims),
         :ok <-
           check(MessageIds.claim("jwt", jti, exp + Sso.clock_skew()), "jti was already used") do
      Identity.build(
        claim(claims, settings["sso_attr_email"], "email"),
        claim(claims, settings["sso_attr_name"], "name"),
        claim(claims, settings["sso_attr_role"], nil)
      )
    end
  end

  defp signer(algorithm, secret) do
    key = if String.starts_with?(algorithm, "HS"), do: secret, else: %{"pem" => secret}
    {:ok, Joken.Signer.create(algorithm, key)}
  rescue
    _ -> {:error, "the configured key does not suit #{algorithm}"}
  end

  # Joken.Signer.verify/2 calls JOSE.JWT.verify_strict/3 with only the
  # configured algorithm allowed.
  defp verify(token, signer) do
    case Joken.Signer.verify(token, signer) do
      {:ok, claims} when is_map(claims) -> {:ok, claims}
      _ -> {:error, "the signature or algorithm is not valid"}
    end
  rescue
    _ -> {:error, "the token is malformed"}
  end

  defp expiry(%{"exp" => exp}) when is_number(exp) do
    if now() > exp + Sso.clock_skew(),
      do: {:error, "the token has expired"},
      else: {:ok, trunc(exp)}
  end

  defp expiry(_claims), do: {:error, "the token has no exp claim"}

  defp not_before(claims) do
    limit = now() + Sso.clock_skew()

    cond do
      future?(claims["nbf"], limit) -> {:error, "the token is not valid yet (nbf)"}
      future?(claims["iat"], limit) -> {:error, "the token was issued in the future (iat)"}
      true -> :ok
    end
  end

  defp future?(value, limit) when is_number(value), do: value > limit
  defp future?(nil, _limit), do: false
  defp future?(_value, _limit), do: true

  defp audience(claims, expected) do
    audiences =
      case claims["aud"] do
        aud when is_binary(aud) -> [aud]
        aud when is_list(aud) -> Enum.filter(aud, &is_binary/1)
        _ -> []
      end

    check(expected != "" and expected in audiences, "aud does not name this application")
  end

  defp jti(%{"jti" => jti}) when is_binary(jti) and jti != "", do: {:ok, jti}
  defp jti(_claims), do: {:error, "the token has no jti claim"}

  defp claim(claims, name, fallback) do
    value =
      case present(name) do
        nil -> nil
        name -> claims[name]
      end

    value = if is_nil(value) and fallback, do: claims[fallback], else: value
    if is_binary(value), do: String.trim(value), else: ""
  end

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:error, reason}

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil

  defp now, do: System.os_time(:second)
end
