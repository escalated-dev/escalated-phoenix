defmodule Escalated.Services.MentionService do
  @moduledoc """
  Resolves and records @mentions found in internal notes.

  Ports the Laravel `MentionService`. The lifecycle is:

    1. `extract_mentions/1` — pull raw handles out of a note body. Two formats
       are supported, mirroring the reference: `@username` (and dotted
       `@first.last`) and `@{Full Name}` for display names containing spaces.
    2. `resolve_mentions/1` — match each handle against the host user table
       (`Escalated.user_schema/0`) by display name or email, returning the
       matched host user ids. Unknown handles resolve to nothing.
    3. `process_mentions/3` — persist one `Escalated.Schemas.Mention` per
       resolved user (skipping the author mentioning themselves) and hand the
       delivery off to the host via the `agent_mentioned` action hook.

  Like `Escalated.Services.Followers`, the package abstracts the host user
  table and owns no notification transport of its own, so notification is a
  `Escalated.Plugins.Hooks.do_action("agent_mentioned", [mention, reply,
  ticket])` fan-out the host subscribes to (mail, database, broadcast, ...).
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Plugins.Hooks
  alias Escalated.Schemas.Mention

  @braced_regex ~r/@\{([^}]+)\}/
  @simple_regex ~r/@(\w+(?:\.\w+)*)/
  @suggestion_limit 10

  @doc """
  Extract mentioned handles from a note/reply body.

  Returns a de-duplicated, trimmed list of the raw handles (usernames, dotted
  usernames, and braced display names). Resolution to users happens in
  `resolve_mentions/1`.
  """
  @spec extract_mentions(String.t() | nil) :: [String.t()]
  def extract_mentions(nil), do: []
  def extract_mentions(""), do: []

  def extract_mentions(text) when is_binary(text) do
    braced =
      @braced_regex
      |> Regex.scan(text)
      |> Enum.map(fn [_, name] -> name end)

    # Strip braced spans first so their inner words aren't re-matched by the
    # simple pattern (`@{Full Name}` should not also yield `Full`).
    simple =
      @braced_regex
      |> Regex.replace(text, "")
      |> then(&Regex.scan(@simple_regex, &1))
      |> Enum.map(fn [_, name] -> name end)

    (braced ++ simple)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def extract_mentions(_), do: []

  @doc """
  Resolve a list of handles to host user ids.

  Matches each handle against the host user's display name (when present) or
  email, exactly as the Laravel reference does. Returns the de-duplicated list
  of matched ids; handles that match no user are dropped.
  """
  @spec resolve_mentions([String.t()]) :: [term()]
  def resolve_mentions(handles) when is_list(handles) do
    names =
      handles
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case names do
      [] -> []
      _ -> query_user_ids(names)
    end
  end

  @doc """
  Extract, resolve and record every mention in `reply`'s body.

  Convenience entry point used by the ticket reply flow. Returns the list of
  persisted `Mention` structs.
  """
  @spec process_reply_mentions(map(), map()) :: [Mention.t()]
  def process_reply_mentions(reply, ticket) do
    reply
    |> Map.get(:body)
    |> extract_mentions()
    |> resolve_mentions()
    |> then(&process_mentions(reply, ticket, &1))
  end

  @doc """
  Persist a mention per resolved user and notify each via the host hook.

  Skips the author mentioning themselves and any `(reply_id, user_id)` pair
  that already exists (the unique index). Returns the newly created mentions.
  """
  @spec process_mentions(map(), map(), [term()]) :: [Mention.t()]
  def process_mentions(_reply, _ticket, []), do: []

  def process_mentions(reply, ticket, user_ids) do
    author_id = Map.get(reply, :author_id)

    user_ids
    |> Enum.uniq()
    |> Enum.reject(&self_mention?(&1, author_id))
    |> Enum.map(&create_and_notify(reply, ticket, &1))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Search host agents by display name or email for @mention autocomplete.

  Mirrors the Laravel `getAgentSuggestions`: a case-insensitive `LIKE` match
  restricted to agent/admin users, capped at #{@suggestion_limit} results, each
  shaped as `%{id, name, email}`.
  """
  @spec agent_suggestions(String.t() | nil) :: [map()]
  def agent_suggestions(query) when is_binary(query) do
    case String.trim(query) do
      "" -> []
      term -> search_agents(term)
    end
  end

  def agent_suggestions(_), do: []

  @doc """
  Extract the local-part of an email address (`john@example.com` -> `john`).
  """
  @spec extract_username_from_email(term()) :: String.t()
  def extract_username_from_email(email) when is_binary(email) do
    email |> String.split("@") |> List.first() |> Kernel.||("")
  end

  def extract_username_from_email(_), do: ""

  # --- private helpers ---

  defp query_user_ids(names) do
    repo = Escalated.repo()
    schema = Escalated.user_schema()

    schema
    |> match_query(names)
    |> repo.all()
    |> Enum.uniq()
  end

  defp match_query(schema, names) do
    base = from(u in schema, select: u.id)

    if schema_has_field?(schema, :name) do
      from(u in base, where: u.name in ^names or u.email in ^names)
    else
      from(u in base, where: u.email in ^names)
    end
  end

  defp create_and_notify(reply, ticket, user_id) do
    %Mention{}
    |> Mention.changeset(%{reply_id: Map.get(reply, :id), user_id: user_id})
    |> Escalated.repo().insert(on_conflict: :nothing, conflict_target: [:reply_id, :user_id])
    |> case do
      {:ok, %Mention{id: id} = mention} when not is_nil(id) ->
        Hooks.do_action("agent_mentioned", [mention, reply, ticket])
        mention

      _ ->
        nil
    end
  end

  defp self_mention?(_user_id, nil), do: false
  defp self_mention?(user_id, author_id), do: to_string(user_id) == to_string(author_id)

  defp search_agents(term) do
    repo = Escalated.repo()
    schema = Escalated.user_schema()
    pattern = "%#{term}%"

    schema
    |> search_query(pattern)
    |> repo.all()
    |> Enum.map(fn user ->
      %{id: Map.get(user, :id), name: Map.get(user, :name), email: Map.get(user, :email)}
    end)
  end

  defp search_query(schema, pattern) do
    schema
    |> name_or_email_like(pattern)
    |> restrict_to_agents(schema)
    |> then(&from(u in &1, limit: @suggestion_limit))
  end

  defp name_or_email_like(schema, pattern) do
    if schema_has_field?(schema, :name) do
      from(u in schema, where: like(u.email, ^pattern) or like(u.name, ^pattern))
    else
      from(u in schema, where: like(u.email, ^pattern))
    end
  end

  defp restrict_to_agents(query, schema) do
    cond do
      schema_has_field?(schema, :is_agent) and schema_has_field?(schema, :is_admin) ->
        from(u in query, where: u.is_agent == true or u.is_admin == true)

      schema_has_field?(schema, :is_agent) ->
        from(u in query, where: u.is_agent == true)

      true ->
        query
    end
  end

  defp schema_has_field?(schema, field) do
    field in schema.__schema__(:fields)
  rescue
    _ -> false
  end
end
