defmodule Escalated.Schemas.SideConversationTest do
  use Escalated.DataCase, async: false

  import Ecto.Query

  alias Escalated.Schemas.{SideConversation, SideConversationReply, Ticket}

  defp repo, do: Escalated.repo()

  defp insert_ticket! do
    {:ok, t} = %Ticket{} |> Ticket.changeset(%{subject: "S", description: "D"}) |> repo().insert()
    t
  end

  defp insert_conversation!(ticket, attrs \\ %{}) do
    {:ok, sc} =
      %SideConversation{}
      |> SideConversation.changeset(
        Map.merge(%{ticket_id: ticket.id, subject: "Vendor", channel: "internal"}, attrs)
      )
      |> repo().insert()

    sc
  end

  describe "SideConversation.changeset/2" do
    test "is valid with required fields and known channel/status" do
      assert SideConversation.changeset(%SideConversation{}, %{
               ticket_id: 1,
               subject: "Q",
               channel: "email"
             }).valid?
    end

    test "rejects an unknown channel" do
      refute SideConversation.changeset(%SideConversation{}, %{
               ticket_id: 1,
               subject: "Q",
               channel: "carrier-pigeon"
             }).valid?
    end

    test "requires ticket_id and subject" do
      refute SideConversation.changeset(%SideConversation{}, %{channel: "internal"}).valid?
    end
  end

  describe "SideConversationReply.changeset/2" do
    test "requires a body" do
      refute SideConversationReply.changeset(%SideConversationReply{}, %{side_conversation_id: 1}).valid?

      assert SideConversationReply.changeset(%SideConversationReply{}, %{
               side_conversation_id: 1,
               body: "hi"
             }).valid?
    end
  end

  describe "persistence + open scope" do
    test "a conversation holds replies and the open scope excludes closed ones" do
      ticket = insert_ticket!()
      open_sc = insert_conversation!(ticket)
      closed_sc = insert_conversation!(ticket, %{status: "closed"})

      {:ok, _} =
        %SideConversationReply{}
        |> SideConversationReply.changeset(%{side_conversation_id: open_sc.id, body: "first"})
        |> repo().insert()

      replies =
        repo().all(from(r in SideConversationReply, where: r.side_conversation_id == ^open_sc.id))

      assert length(replies) == 1

      open_ids = SideConversation.open() |> repo().all() |> Enum.map(& &1.id)
      assert open_sc.id in open_ids
      refute closed_sc.id in open_ids
    end
  end

  describe "modules load" do
    test "the side-conversation controller is compiled" do
      assert Code.ensure_loaded?(Escalated.Controllers.Admin.SideConversationController)
    end
  end
end
