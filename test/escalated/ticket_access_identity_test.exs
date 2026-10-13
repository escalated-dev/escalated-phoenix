defmodule Escalated.TicketAccessIdentityTest do
  use Escalated.DataCase, async: false
  alias Escalated.Schemas.{Department, DepartmentAgent, Ticket}
  alias Escalated.TicketVisibility

  test "department membership honors configured table prefix and host string identities" do
    Application.put_env(:escalated, :visibility, :department)
    Application.put_env(:escalated, :agent_check, fn _ -> true end)
    Application.put_env(:escalated, :admin_check, fn _ -> false end)

    on_exit(fn ->
      for key <- [:visibility, :agent_check, :admin_check],
          do: Application.delete_env(:escalated, key)
    end)

    repo = Escalated.repo()
    department = repo.insert!(Department.changeset(%Department{}, %{name: "Identity"}))

    {:ok, ticket} =
      Escalated.Services.TicketService.create(%{
        subject: "Identity",
        description: "Body",
        department_id: department.id
      })

    pairs =
      if DepartmentAgent.__schema__(:type, :agent_id) == :string,
        do: [{"Agent-A", "agent-a"}, {"007", "7"}, {"Agent", "Agent "}],
        else: [{900, 901}]

    for {member, stranger} <- pairs do
      repo.insert!(
        DepartmentAgent.changeset(%DepartmentAgent{}, %{
          department_id: department.id,
          agent_id: member
        })
      )

      TicketVisibility.with_user(%{id: member}, fn -> assert repo.get(Ticket, ticket.id) end)

      TicketVisibility.with_user(%{id: stranger}, fn ->
        assert is_nil(repo.get(Ticket, ticket.id))
      end)
    end

    assert Ticket.__schema__(:source) == Escalated.table_name("tickets")
  end
end
