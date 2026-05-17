defmodule Escalated.SkillRouting do
  @moduledoc """
  Skill-based routing: which agents match a ticket given explicit tag and
  department mappings on skills.

  See escalated-developer-context ADR
  `2026-05-13-skills-routing-explicit-mapping.md`.
  """

  import Ecto.Query

  alias Escalated.Schemas.{AgentSkill, SkillRoutingDepartment, SkillRoutingTag, Ticket}

  @open_statuses ~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened)

  @doc """
  Returns users that have **all** skills required for the ticket, ordered by
  sum of proficiency (desc), then ascending open-ticket load on assigned tickets.
  """
  def find_matching_agents(ticket_like) do
    repo = Escalated.repo()

    case load_ticket(repo, ticket_like) do
      nil ->
        []

      ticket ->
        tag_ids = Enum.map(ticket.tags || [], & &1.id)
        dept_id = ticket.department_id

        required =
          MapSet.union(skill_ids_for_tags(repo, tag_ids), skill_ids_for_department(repo, dept_id))
          |> MapSet.to_list()

        if required == [] do
          []
        else
          match_agents(repo, required)
        end
    end
  end

  defp load_ticket(repo, %Ticket{} = t) do
    cond do
      Ecto.assoc_loaded?(t.tags) ->
        t

      is_nil(t.id) ->
        t

      true ->
        case repo.get(Ticket, t.id) do
          nil -> nil
          row -> repo.preload(row, :tags)
        end
    end
  end

  defp load_ticket(repo, %{id: id}) when not is_nil(id) do
    case repo.get(Ticket, id) do
      nil -> nil
      t -> repo.preload(t, :tags)
    end
  end

  defp load_ticket(_repo, _), do: nil

  defp skill_ids_for_tags(_repo, []), do: MapSet.new()

  defp skill_ids_for_tags(repo, tag_ids) do
    from(rt in SkillRoutingTag,
      where: rt.tag_id in ^tag_ids,
      distinct: true,
      select: rt.skill_id
    )
    |> repo.all()
    |> MapSet.new()
  end

  defp skill_ids_for_department(_repo, nil), do: MapSet.new()

  defp skill_ids_for_department(repo, dept_id) do
    from(rd in SkillRoutingDepartment,
      where: rd.department_id == ^dept_id,
      distinct: true,
      select: rd.skill_id
    )
    |> repo.all()
    |> MapSet.new()
  end

  defp match_agents(repo, required_skill_ids) do
    req_count = length(required_skill_ids)
    user_schema = Escalated.user_schema()

    candidates =
      from(as in AgentSkill,
        where: as.skill_id in ^required_skill_ids,
        group_by: as.user_id,
        having: fragment("COUNT(DISTINCT skill_id) = ?", ^req_count),
        select: %{user_id: as.user_id, prof_sum: sum(as.proficiency)}
      )
      |> repo.all()

    if candidates == [] do
      []
    else
      uids = Enum.map(candidates, & &1.user_id)

      loads =
        from(t in Ticket,
          where: t.assigned_to in ^uids,
          where: t.status in @open_statuses,
          group_by: t.assigned_to,
          select: {t.assigned_to, count(t.id)}
        )
        |> repo.all()
        |> Map.new()

      candidates
      |> Enum.sort_by(fn row ->
        load = Map.get(loads, row.user_id, 0)
        prof = numeric(row.prof_sum)
        {-prof, load, row.user_id}
      end)
      |> Enum.map(& &1.user_id)
      |> then(fn ordered ->
        users =
          from(u in user_schema, where: u.id in ^ordered)
          |> repo.all()
          |> Map.new(&{&1.id, &1})

        Enum.map(ordered, &Map.get(users, &1))
        |> Enum.reject(&is_nil/1)
      end)
    end
  end

  defp numeric(%Decimal{} = d), do: Decimal.to_integer(d)
  defp numeric(n) when is_integer(n), do: n
  defp numeric(n) when is_float(n), do: round(n)
  defp numeric(nil), do: 0
  defp numeric(_), do: 0
end
