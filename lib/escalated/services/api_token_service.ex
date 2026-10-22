defmodule Escalated.Services.ApiTokenService do
  @moduledoc """
  Issues, finds and revokes API tokens (`Escalated.Schemas.ApiToken`), as
  escalated-laravel's `ApiToken::createToken/findByPlainText`.

  A token is 32 random bytes as 64 hex characters. Only its SHA-256 digest is
  stored, so the plain text exists once, in the result of `create/4`, and a
  leaked table holds nothing that authenticates.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.ApiToken

  # last_used_at / last_used_ip are written at most this often per token, so
  # an integration polling the API does not cost a write per request.
  @touch_interval_seconds 5 * 60

  @doc """
  Creates a token for `user_id`. Returns `{:ok, %{token: %ApiToken{},
  plain_text_token: String.t()}}`; the plain text is not kept anywhere.
  """
  def create(user_id, name, abilities, expires_at \\ nil) do
    plain = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    %ApiToken{}
    |> ApiToken.changeset(%{
      user_id: user_id,
      name: name,
      token: digest(plain),
      abilities: abilities,
      expires_at: expires_at && DateTime.truncate(expires_at, :second)
    })
    |> repo().insert()
    |> case do
      {:ok, token} -> {:ok, %{token: token, plain_text_token: plain}}
      error -> error
    end
  end

  @doc "The token whose plain text is `plain`, or nil."
  def find_by_plain_text(plain) when is_binary(plain) and plain != "",
    do: repo().get_by(ApiToken, token: digest(plain))

  def find_by_plain_text(_plain), do: nil

  @doc "Every token, newest first."
  def list do
    from(t in ApiToken, order_by: [desc: t.inserted_at, desc: t.id]) |> repo().all()
  end

  @doc "The token with `id`, or nil."
  def get(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> repo().get(ApiToken, int)
      _ -> nil
    end
  end

  @doc "Changes a token's name and/or abilities."
  def update(%ApiToken{} = token, attrs),
    do: token |> ApiToken.update_changeset(attrs) |> repo().update()

  @doc "Revokes (deletes) a token."
  def revoke(%ApiToken{} = token), do: repo().delete(token)

  @doc """
  Records that `token` was just used from `ip`, unless it was already recorded
  in the last five minutes.
  """
  def touch(%ApiToken{} = token, ip) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if is_nil(token.last_used_at) or
         DateTime.diff(now, token.last_used_at) >= @touch_interval_seconds do
      token
      |> Ecto.Changeset.change(last_used_at: now, last_used_ip: ip)
      |> repo().update()
    else
      {:ok, token}
    end
  end

  @doc "The stored form of a plain-text token: its SHA-256 digest, lowercase hex."
  def digest(plain), do: :crypto.hash(:sha256, plain) |> Base.encode16(case: :lower)

  defp repo, do: Escalated.repo()
end
