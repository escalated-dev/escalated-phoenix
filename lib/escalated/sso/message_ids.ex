defmodule Escalated.Sso.MessageIds do
  @moduledoc """
  Single-use SSO message IDs, kept in `sso_message_ids` (ADR
  2026-10-29-configurable-access-features). The JWT provider claims each
  token's `jti` here, so a token works once. Expired rows are pruned on
  every write.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.SsoMessageId

  @max_length 191

  @doc """
  Records `id` of `kind` as used until `expires_at` (Unix seconds). True the
  first time; false when it was already used (a replay) or is too long to
  store.
  """
  def claim(kind, id, expires_at)
      when is_binary(kind) and is_binary(id) and is_integer(expires_at) do
    prune()

    cond do
      id == "" or String.length(id) > @max_length ->
        false

      used?(kind, id) ->
        false

      true ->
        try do
          repo().insert!(%SsoMessageId{kind: kind, message_id: id, expires_at: expires_at})
          true
        rescue
          # Two requests with the same ID at once: the unique index decides.
          Ecto.ConstraintError -> false
        end
    end
  end

  @doc "Whether `id` of `kind` is recorded and not yet expired."
  def used?(kind, id) do
    now = System.os_time(:second)

    from(m in SsoMessageId,
      where: m.kind == ^kind and m.message_id == ^id and m.expires_at > ^now,
      select: m.id
    )
    |> repo().all()
    |> Kernel.!=([])
  end

  @doc "Deletes expired rows."
  def prune do
    now = System.os_time(:second)
    from(m in SsoMessageId, where: m.expires_at <= ^now) |> repo().delete_all()
    :ok
  end

  defp repo, do: Escalated.repo()
end
