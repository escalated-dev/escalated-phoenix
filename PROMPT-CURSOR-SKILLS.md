# Cursor task: skills-management parity for escalated-phoenix (greenfield)

Self-contained brief. Read fully before doing anything.

## Goal
Greenfield: implement the canonical Skills-management contract on this Phoenix plugin.

**Tracking issue:** https://github.com/escalated-dev/escalated-phoenix/issues/65
**Canonical contract:** https://github.com/escalated-dev/escalated-developer-context/blob/main/domain-model/skills-management.md
**ADR:** https://github.com/escalated-dev/escalated-developer-context/blob/main/decisions/2026-05-13-skills-routing-explicit-mapping.md
**Reference impl:** https://github.com/escalated-dev/escalated-nestjs/pull/45

## Current state
No skills code. Phoenix / Elixir backend with Ecto. Reference controllers in `lib/escalated/controllers/admin/`.

## Deliverables

1. **Ecto migrations** (`priv/repo/migrations/`): three new tables matching the contract schema — `escalated_skills`, `escalated_agent_skills` (with proficiency 1..5), `escalated_skill_routing_tags`, `escalated_skill_routing_departments`.

2. **Ecto schemas** (`lib/escalated/schemas/`): `Skill`, `AgentSkill`, `SkillRoutingTag`, `SkillRoutingDepartment`. `Skill` has `has_many :routing_tags, ...`, `has_many :routing_departments, ...`, `has_many :agent_skills`. Add a `description` field.

3. **Context module** (`lib/escalated/skills.ex`): functions `list_for_admin/0`, `find_for_edit/1`, `form_context/0`, `create_skill/1`, `update_skill/2`, `delete_skill/1`. Use `Ecto.Multi` for transactional relation sync.

4. **Routing context** (`lib/escalated/skill_routing.ex`): `find_matching_agents/1` implementing the explicit-mapping logic.

5. **Controller** (`lib/escalated/controllers/admin/skill_controller.ex`): 6 actions, JSON response per the contract. Plug-based auth.

6. **Router** (`lib/escalated_web/router.ex` or whatever path): `resources "/skills", Admin.SkillController` under the admin scope, helpers named `Routes.admin_skill_path`.

7. **Sidebar wire-up**: surface skills index in the admin nav (whatever the existing plugin uses).

8. **Tests** (`test/`): ExUnit controller + context tests covering CRUD, routing service.

## Process
1. `git checkout -b feat/admin-skills-management`.
2. Read the contract + reference.
3. Implement and commit logically, reference #65.
4. `mix test`, `mix format --check-formatted`, `mix credo` (if used).
5. Push, open PR `feat(skills): admin skills management parity (#65)`.

## Constraints
- Phoenix 1.7+ / Elixir idioms.
- snake_case at the wire — natural for Elixir.
- Stop after pushing. Don't include the PROMPT file.
