defmodule Escalated.Skills do
  @moduledoc """
  Admin CRUD and form helpers for `escalated_skills` + routing joins +
  `escalated_agent_skills`.

  Mirrors the portfolio `SkillService` contract in
  escalated-developer-context/domain-model/skills-management.md.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Escalated.Schemas.{
    AgentSkill,
    Department,
    Skill,
    SkillRoutingDepartment,
    SkillRoutingTag,
    Tag
  }

  @doc """
  Rows for the admin Skills index, including counter fields.
  """
  def list_for_admin do
    repo = Escalated.repo()

    Skill
    |> order_by([s], asc: s.name)
    |> preload([:skill_routing_tags, :skill_routing_departments, :agent_skills])
    |> repo.all()
    |> Enum.map(&skill_to_index_row/1)
  end

  defp skill_to_index_row(%Skill{} = s) do
    %{
      id: s.id,
      name: s.name,
      agents_count: length(s.agent_skills || []),
      routing_tags_count: length(s.skill_routing_tags || []),
      routing_departments_count: length(s.skill_routing_departments || []),
      updated_at: s.updated_at
    }
  end

  @doc """
  Skill payload for the edit form plus routing + agent proficiency arrays.
  """
  def find_for_edit(id) do
    repo = Escalated.repo()

    case repo.get(Skill, id) do
      nil ->
        nil

      skill ->
        skill =
          repo.preload(skill, [:skill_routing_tags, :skill_routing_departments, :agent_skills])

        %{
          id: skill.id,
          name: skill.name,
          description: skill.description,
          routing_tag_ids: Enum.map(skill.skill_routing_tags, & &1.tag_id),
          routing_department_ids: Enum.map(skill.skill_routing_departments, & &1.department_id),
          agents:
            Enum.map(skill.agent_skills, fn as ->
              %{user_id: as.user_id, proficiency: as.proficiency}
            end)
        }
    end
  end

  @doc """
  Dropdown sources for the Skills form (`available*` props).
  """
  def form_context do
    repo = Escalated.repo()
    user_schema = Escalated.user_schema()

    agents =
      from(u in user_schema,
        where: u.is_agent == true,
        order_by: [asc: u.id]
      )
      |> repo.all()
      |> Enum.map(fn u ->
        %{
          id: u.id,
          name: Map.get(u, :name),
          email: Map.get(u, :email)
        }
      end)

    tags =
      Tag
      |> Tag.ordered()
      |> repo.all()
      |> Enum.map(fn t -> %{id: t.id, name: t.name} end)

    departments =
      Department
      |> Department.ordered()
      |> repo.all()
      |> Enum.map(fn d -> %{id: d.id, name: d.name} end)

    %{
      availableAgents: agents,
      availableTags: tags,
      availableDepartments: departments
    }
  end

  @doc """
  Creates a skill and syncs routing tags, routing departments, and agent rows.
  """
  def create_skill(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)
    repo = Escalated.repo()

    with :ok <- validate_attrs(repo, attrs) do
      run_create(repo, attrs)
    end
  end

  defp run_create(repo, attrs) do
    Multi.new()
    |> Multi.insert(:skill, Skill.changeset(%Skill{}, cast_skill_fields(attrs)))
    |> Multi.merge(fn %{skill: skill} ->
      sync_relations_multi(skill.id, attrs)
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{skill: skill}} -> {:ok, skill}
      {:error, :skill, cs, _} -> {:error, cs}
      {:error, failed, v, _} -> {:error, {failed, v}}
    end
  end

  @doc """
  Updates a skill and replaces routing + agent rows transactionally.
  """
  def update_skill(id, attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)
    repo = Escalated.repo()

    case repo.get(Skill, id) do
      nil ->
        {:error, :not_found}

      %Skill{} = skill ->
        with :ok <- validate_attrs(repo, attrs) do
          run_update(repo, skill, id, attrs)
        end
    end
  end

  defp run_update(repo, skill, id, attrs) do
    Multi.new()
    |> Multi.update(:skill, Skill.changeset(skill, cast_skill_fields(attrs)))
    |> Multi.delete_all(:purge_tags, from(rt in SkillRoutingTag, where: rt.skill_id == ^id))
    |> Multi.delete_all(:purge_depts, from(rd in SkillRoutingDepartment, where: rd.skill_id == ^id))
    |> Multi.delete_all(:purge_agents, from(as in AgentSkill, where: as.skill_id == ^id))
    |> Multi.merge(fn _ ->
      sync_relations_multi(id, attrs)
    end)
    |> repo.transaction()
    |> case do
      {:ok, %{skill: skill}} -> {:ok, skill}
      {:error, :skill, cs, _} -> {:error, cs}
      {:error, failed, v, _} -> {:error, {failed, v}}
    end
  end

  @doc """
  Deletes a skill (cascades routing + agent rows at the DB layer when supported,
  or via FK on_delete in migrations).
  """
  def delete_skill(id) do
    repo = Escalated.repo()

    case repo.get(Skill, id) do
      nil -> {:error, :not_found}
      skill -> repo.delete(skill)
    end
  end

  defp validate_attrs(repo, attrs) do
    cs = Skill.changeset(%Skill{}, cast_skill_fields(attrs))

    cs =
      Enum.reduce(attrs.routing_tag_ids, cs, fn tid, acc ->
        if repo.get(Tag, tid),
          do: acc,
          else: Ecto.Changeset.add_error(acc, :routing_tag_ids, "invalid tag id")
      end)

    cs =
      Enum.reduce(attrs.routing_department_ids, cs, fn did, acc ->
        if repo.get(Department, did),
          do: acc,
          else: Ecto.Changeset.add_error(acc, :routing_department_ids, "invalid department id")
      end)

    user_schema = Escalated.user_schema()

    cs =
      Enum.reduce(attrs.agents, cs, fn %{user_id: uid}, acc ->
        case repo.get(user_schema, uid) do
          nil ->
            Ecto.Changeset.add_error(acc, :agents, "invalid user id")

          u ->
            if Map.get(u, :is_agent, false),
              do: acc,
              else: Ecto.Changeset.add_error(acc, :agents, "user must be an agent")
        end
      end)

    if cs.valid?, do: :ok, else: {:error, cs}
  end

  defp cast_skill_fields(attrs) do
    %{"name" => attrs.name, "description" => attrs.description}
  end

  defp normalize_attrs(params) when is_map(params) do
    p = for {k, v} <- params, into: %{}, do: {to_string(k), v}

    %{
      name: p["name"],
      description: blank_to_nil(p["description"]),
      routing_tag_ids: normalize_id_list(p["routing_tag_ids"]),
      routing_department_ids: normalize_id_list(p["routing_department_ids"]),
      agents: normalize_agents(p["agents"])
    }
  end

  defp blank_to_nil(v) when v in [nil, ""], do: nil
  defp blank_to_nil(v), do: to_string(v)

  defp normalize_id_list(nil), do: []
  defp normalize_id_list(list) when is_list(list), do: Enum.map(list, &to_int/1) |> Enum.reject(&is_nil/1)

  defp normalize_id_list(_), do: []

  defp normalize_agents(nil), do: []

  defp normalize_agents(list) when is_list(list) do
    Enum.map(list, fn row ->
      row = for {k, v} <- row || %{}, into: %{}, do: {to_string(k), v}

      prof =
        case row["proficiency"] do
          nil -> 3
          "" -> 3
          n -> to_int(n) || 3
        end

      prof = min(5, max(1, prof))

      %{user_id: to_int(row["user_id"]), proficiency: prof}
    end)
    |> Enum.filter(fn %{user_id: uid} -> uid != nil end)
    |> Enum.uniq_by(& &1.user_id)
  end

  defp normalize_agents(_), do: []

  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp to_int(_), do: nil

  defp sync_relations_multi(skill_id, attrs) do
    tag_rows =
      for tid <- attrs.routing_tag_ids do
        %{skill_id: skill_id, tag_id: tid}
      end

    dept_rows =
      for did <- attrs.routing_department_ids do
        %{skill_id: skill_id, department_id: did}
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    agent_rows =
      for a <- attrs.agents do
        %{
          skill_id: skill_id,
          user_id: a.user_id,
          proficiency: a.proficiency,
          inserted_at: now,
          updated_at: now
        }
      end

    Multi.new()
    |> multi_insert_all(:tags, SkillRoutingTag, tag_rows)
    |> multi_insert_all(:depts, SkillRoutingDepartment, dept_rows)
    |> multi_insert_all(:agents, AgentSkill, agent_rows)
  end

  defp multi_insert_all(%Ecto.Multi{} = m, step, schema, rows) do
    if rows == [] do
      Multi.run(m, step, fn _, _ -> {:ok, 0} end)
    else
      Multi.insert_all(m, step, schema, rows)
    end
  end
end
