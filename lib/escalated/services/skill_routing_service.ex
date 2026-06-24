defmodule Escalated.Services.SkillRoutingService do
  @moduledoc """
  Ranks agents by skill fit for a ticket. Mirrors the Laravel
  `SkillRoutingService`: explicit skill→tag / skill→department routing
  rules win; a skill with no rules falls back to name-based tag matching.
  Candidates are ordered by matched-skill count, then total proficiency,
  then current open-ticket load, then display name.
  """
  import Ecto.Query

  alias Escalated.Schemas.{
    AgentProfile,
    AgentSkill,
    Skill,
    SkillRoutingDepartment,
    SkillRoutingTag,
    Ticket
  }

  @doc """
  Ranked candidate agents for `ticket` as a list of maps:
  `%{user_id, display_name, matched_skill_count, total_skill_proficiency,
  open_tickets_count}`. Empty when the ticket carries no tags/department
  or when no skilled agent matches.
  """
  def find_matching_agents(%Ticket{} = ticket) do
    repo = Escalated.repo()
    ticket = repo.preload(ticket, :tags)

    tag_ids = Enum.map(ticket.tags, & &1.id)
    tag_names = Enum.map(ticket.tags, &String.downcase(&1.name))

    if tag_ids == [] and is_nil(ticket.department_id) do
      []
    else
      repo
      |> matching_skill_ids(tag_ids, tag_names, ticket.department_id)
      |> rank_agents(repo)
    end
  end

  defp matching_skill_ids(repo, tag_ids, tag_names, dept_id) do
    tags_by_skill =
      group_pairs(repo.all(from(t in SkillRoutingTag, select: {t.skill_id, t.tag_id})))

    depts_by_skill =
      group_pairs(
        repo.all(from(d in SkillRoutingDepartment, select: {d.skill_id, d.department_id}))
      )

    repo.all(Skill)
    |> Enum.filter(fn skill ->
      skill_matches?(
        skill,
        Map.get(tags_by_skill, skill.id, []),
        Map.get(depts_by_skill, skill.id, []),
        tag_ids,
        tag_names,
        dept_id
      )
    end)
    |> Enum.map(& &1.id)
  end

  defp skill_matches?(skill, routing_tag_ids, routing_dept_ids, tag_ids, tag_names, dept_id) do
    if routing_tag_ids != [] or routing_dept_ids != [] do
      (routing_tag_ids != [] and Enum.any?(routing_tag_ids, &(&1 in tag_ids))) or
        (not is_nil(dept_id) and dept_id in routing_dept_ids)
    else
      String.downcase(skill.name) in tag_names
    end
  end

  defp rank_agents([], _repo), do: []

  defp rank_agents(skill_ids, repo) do
    rows =
      repo.all(
        from(a in AgentSkill,
          where: a.skill_id in ^skill_ids,
          select: {a.user_id, a.skill_id, a.proficiency}
        )
      )

    rank_rows(rows, repo, MapSet.new(skill_ids))
  end

  defp rank_rows([], _repo, _skill_set), do: []

  defp rank_rows(rows, repo, skill_set) do
    user_ids = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq()
    open_counts = open_ticket_counts(repo, user_ids)
    names = display_names(repo, user_ids)

    rows
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {user_id, urows} ->
      score_agent(user_id, urows, skill_set, open_counts, names)
    end)
    |> Enum.filter(&(&1.matched_skill_count > 0))
    |> Enum.sort_by(&sort_key/1)
  end

  defp score_agent(user_id, urows, skill_set, open_counts, names) do
    matched =
      urows
      |> Enum.map(&elem(&1, 1))
      |> Enum.filter(&MapSet.member?(skill_set, &1))
      |> Enum.uniq()
      |> length()

    %{
      user_id: user_id,
      display_name: Map.get(names, user_id),
      matched_skill_count: matched,
      total_skill_proficiency: urows |> Enum.map(&elem(&1, 2)) |> Enum.sum(),
      open_tickets_count: Map.get(open_counts, user_id, 0)
    }
  end

  defp sort_key(agent) do
    {-agent.matched_skill_count, -agent.total_skill_proficiency, agent.open_tickets_count,
     String.downcase(agent.display_name || "")}
  end

  defp open_ticket_counts(repo, user_ids) do
    Ticket.by_open()
    |> where([t], t.assigned_to in ^user_ids)
    |> group_by([t], t.assigned_to)
    |> select([t], {t.assigned_to, count(t.id)})
    |> repo.all()
    |> Map.new()
  end

  defp display_names(repo, user_ids) do
    from(p in AgentProfile, where: p.user_id in ^user_ids, select: {p.user_id, p.display_name})
    |> repo.all()
    |> Map.new()
  end

  defp group_pairs(pairs) do
    Enum.reduce(pairs, %{}, fn {key, value}, acc ->
      Map.update(acc, key, [value], &[value | &1])
    end)
  end
end
