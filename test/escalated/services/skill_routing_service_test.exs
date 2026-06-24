defmodule Escalated.Services.SkillRoutingServiceTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{AgentSkill, Skill, SkillRoutingTag, Tag, Ticket}
  alias Escalated.Services.SkillRoutingService

  defp repo, do: Escalated.repo()

  defp create_tag!(name) do
    {:ok, t} = %Tag{} |> Tag.changeset(%{name: name}) |> repo().insert()
    t
  end

  defp create_skill!(name) do
    {:ok, s} = %Skill{} |> Skill.changeset(%{name: name}) |> repo().insert()
    s
  end

  defp route_tag!(skill, tag) do
    {:ok, _} =
      %SkillRoutingTag{}
      |> SkillRoutingTag.changeset(%{skill_id: skill.id, tag_id: tag.id})
      |> repo().insert()
  end

  defp give_skill!(user_id, skill, proficiency) do
    {:ok, _} =
      %AgentSkill{}
      |> AgentSkill.changeset(%{user_id: user_id, skill_id: skill.id, proficiency: proficiency})
      |> repo().insert()
  end

  defp ticket_with_tags!(tags) do
    {:ok, ticket} =
      %Ticket{} |> Ticket.changeset(%{subject: "S", description: "D"}) |> repo().insert()

    case Enum.map(tags, &%{ticket_id: ticket.id, tag_id: &1.id}) do
      [] -> :ok
      rows -> repo().insert_all("escalated_ticket_tags", rows)
    end

    ticket
  end

  test "returns empty when the ticket has no tags or department" do
    assert SkillRoutingService.find_matching_agents(ticket_with_tags!([])) == []
  end

  test "matches via explicit skill->tag routing, ranked by proficiency" do
    tag = create_tag!("billing")
    skill = create_skill!("Billing")
    route_tag!(skill, tag)
    give_skill!(1, skill, 5)
    give_skill!(2, skill, 2)

    result = SkillRoutingService.find_matching_agents(ticket_with_tags!([tag]))

    assert Enum.map(result, & &1.user_id) == [1, 2]
    assert hd(result).matched_skill_count == 1
    assert hd(result).total_skill_proficiency == 5
  end

  test "falls back to skill-name matching when a skill has no routing rules" do
    tag = create_tag!("refunds")
    skill = create_skill!("refunds")
    give_skill!(3, skill, 4)

    assert [%{user_id: 3}] = SkillRoutingService.find_matching_agents(ticket_with_tags!([tag]))
  end

  test "excludes agents whose skills do not match the ticket" do
    tag = create_tag!("billing")
    billing = create_skill!("Billing")
    shipping = create_skill!("Shipping")
    route_tag!(billing, tag)
    give_skill!(1, billing, 5)
    give_skill!(2, shipping, 5)

    result = SkillRoutingService.find_matching_agents(ticket_with_tags!([tag]))
    assert Enum.map(result, & &1.user_id) == [1]
  end

  test "the service module is compiled" do
    assert Code.ensure_loaded?(SkillRoutingService)
  end
end
