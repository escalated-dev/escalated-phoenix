defmodule Escalated.Rendering.UserDirectory do
  @moduledoc """
  Host users as the shared pages show them: `%{id, name, email}`.

  The package stores host user keys only (`assigned_to`, `author_id`,
  `causer_id`, ...). The pages read people by name, so the keys a page needs
  are looked up in one query against `Escalated.user_schema/0` on
  `Escalated.user_repo/0`. A key the host table does not have resolves to
  nothing rather than raising, so a deleted user leaves a blank name, not a
  broken page.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Services.MentionService

  @agent_limit 500

  @doc """
  Looks up `ids` and returns a map from the stringified key to
  `%{id, name, email}`. Use `get/2` to read it.
  """
  def lookup(ids) do
    schema = Escalated.user_schema()

    keys =
      ids
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.flat_map(&cast_key(schema, &1))

    case keys do
      [] ->
        %{}

      keys ->
        from(u in schema, where: u.id in ^keys)
        |> Escalated.user_repo().all()
        |> Map.new(fn user -> {to_string(user.id), person(user)} end)
    end
  end

  @doc "The person for `id` in a `lookup/1` result, or nil."
  def get(_directory, nil), do: nil
  def get(directory, id), do: Map.get(directory, to_string(id))

  @doc "The display name for `id` in a `lookup/1` result, or nil."
  def name(directory, id) do
    case get(directory, id) do
      %{name: name} -> name
      _ -> nil
    end
  end

  @doc """
  The agents and admins an assignee picker offers, as `%{id, name, email}`,
  ordered by name. Uses the same agent test as @mention suggestions.
  """
  def agents do
    schema = Escalated.user_schema()

    schema
    |> MentionService.restrict_to_agents(schema)
    |> then(&from(u in &1, limit: @agent_limit))
    |> Escalated.user_repo().all()
    |> Enum.map(&person/1)
    |> Enum.sort_by(&String.downcase(to_string(&1.name || &1.email || "")))
  end

  @doc "A host user struct or map as `%{id, name, email}`."
  def person(user) do
    %{id: Map.get(user, :id), name: display_name(user), email: Map.get(user, :email)}
  end

  defp display_name(user) do
    name =
      if is_struct(user) and function_exported?(user.__struct__, :name, 1),
        do: user.__struct__.name(user),
        else: Map.get(user, :name)

    case name do
      name when is_binary(name) and name != "" -> name
      _ -> Map.get(user, :email)
    end
  end

  # Keys are stored as the package's user key type, which need not be the host
  # table's primary key type. A key that cannot be cast is no user at all.
  defp cast_key(schema, id) do
    type = schema.__schema__(:type, :id) || :id

    case Ecto.Type.cast(type, id) do
      {:ok, value} when not is_nil(value) -> [value]
      _ -> []
    end
  end
end
