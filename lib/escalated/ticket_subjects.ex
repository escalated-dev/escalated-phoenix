defmodule Escalated.TicketSubjects do
  @moduledoc """
  Configuration helpers and serialization for ticket subjects.
  """

  alias Escalated.Schemas.TicketSubject

  @doc """
  Returns ticket-subjects config as a keyword list.

      config :escalated,
        ticket_subjects: [
          types: ["project", "customer"],
          resolver: &MyApp.TicketSubjects.resolve/2
        ]
  """
  def config do
    case Escalated.config(:ticket_subjects, []) do
      list when is_list(list) -> list
      map when is_map(map) -> Map.to_list(map)
      _ -> []
    end
  end

  @doc """
  Flat allowlist of permitted `subject_type` strings.

  Accepts a list of type strings or a map of alias => type (both keys and values
  are included), matching the Laravel package.
  """
  def allowed_types do
    types = Keyword.get(config(), :types, [])
    flatten_types(types) |> Enum.uniq()
  end

  defp flatten_types(types) when is_map(types) do
    Enum.flat_map(types, fn
      {key, value} when is_binary(key) and is_binary(value) -> [key, value]
      _ -> []
    end)
  end

  defp flatten_types(types) when is_list(types) do
    Enum.flat_map(types, fn
      {key, value} when is_binary(key) and is_binary(value) -> [key, value]
      type when is_binary(type) -> [type]
      _ -> []
    end)
  end

  defp flatten_types(_), do: []

  @doc """
  Returns true when programmatic attach is permitted for `type`.

  An empty allowlist permits any type; a non-empty allowlist restricts attaches.
  """
  def type_allowed?(type) when is_binary(type) do
    case allowed_types() do
      [] -> true
      allowed -> type in allowed
    end
  end

  def type_allowed?(_), do: false

  @doc """
  Returns true when the agent/admin API may attach `type`.

  Requires a non-empty allowlist that includes the type.
  """
  def api_type_allowed?(type) when is_binary(type) do
    allowed = allowed_types()
    allowed != [] and type in allowed
  end

  def api_type_allowed?(_), do: false

  @doc """
  Resolves a host subject struct via the configured `:resolver` fun, or nil.
  """
  def resolve(type, id) when is_binary(type) and is_binary(id) do
    case Keyword.get(config(), :resolver) do
      fun when is_function(fun, 2) -> fun.(type, id)
      _ -> nil
    end
  end

  def resolve(_, _), do: nil

  @doc """
  Serializes ticket subject links for the ticket JSON payload.
  """
  def serialize_links(links) when is_list(links) do
    Enum.map(links, &serialize_link/1)
  end

  def serialize_links(_), do: []

  defp serialize_link(%TicketSubject{} = link) do
    subject = resolve(link.subject_type, link.subject_id)
    presents? = presents_ticket_subject?(subject)
    mod = subject && subject.__struct__

    %{
      type: link.subject_type,
      id: link.subject_id,
      role: link.role,
      title: link_title(link, subject, presents?, mod),
      subtitle: if(presents?, do: mod.ticket_subject_subtitle(subject), else: nil),
      url: if(presents?, do: mod.ticket_subject_url(subject), else: nil),
      color: if(presents?, do: mod.ticket_subject_color(subject), else: nil),
      icon: if(presents?, do: mod.ticket_subject_icon(subject), else: nil),
      missing: is_nil(subject)
    }
  end

  defp presents_ticket_subject?(subject) do
    subject != nil and function_exported?(subject.__struct__, :ticket_subject_title, 1)
  end

  defp link_title(_link, subject, true, mod), do: mod.ticket_subject_title(subject)

  defp link_title(_link, %{name: name}, _, _) when is_binary(name) and name != "",
    do: name

  defp link_title(link, _, _, _),
    do: "#{type_basename(link.subject_type)} ##{link.subject_id}"

  defp type_basename(type) do
    type
    |> String.split(".")
    |> List.last()
  end
end
