defmodule Escalated.Schemas.TicketLinkTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{Ticket, TicketLink}

  defp repo, do: Escalated.repo()

  defp insert_ticket! do
    {:ok, t} =
      %Ticket{} |> Ticket.changeset(%{subject: "S", description: "D"}) |> repo().insert()

    t
  end

  defp link(parent, child, type) do
    %TicketLink{}
    |> TicketLink.changeset(%{
      parent_ticket_id: parent.id,
      child_ticket_id: child.id,
      link_type: type
    })
    |> repo().insert()
  end

  describe "changeset/2" do
    test "accepts the known link types" do
      for type <- TicketLink.link_types() do
        assert TicketLink.changeset(%TicketLink{}, %{
                 parent_ticket_id: 1,
                 child_ticket_id: 2,
                 link_type: type
               }).valid?
      end
    end

    test "rejects an unknown link type" do
      refute TicketLink.changeset(%TicketLink{}, %{
               parent_ticket_id: 1,
               child_ticket_id: 2,
               link_type: "bogus"
             }).valid?
    end

    test "requires parent, child, and link_type" do
      refute TicketLink.changeset(%TicketLink{}, %{}).valid?
    end
  end

  describe "uniqueness" do
    test "the same parent+child+type cannot be duplicated" do
      a = insert_ticket!()
      b = insert_ticket!()

      assert {:ok, _} = link(a, b, "related")
      assert {:error, cs} = link(a, b, "related")
      refute cs.valid?
    end

    test "a different link type between the same tickets is allowed" do
      a = insert_ticket!()
      b = insert_ticket!()

      assert {:ok, _} = link(a, b, "related")
      assert {:ok, _} = link(a, b, "parent_child")
    end
  end

  describe "modules load" do
    test "the ticket-link controller is compiled" do
      assert Code.ensure_loaded?(Escalated.Controllers.Admin.TicketLinkController)
    end
  end
end
