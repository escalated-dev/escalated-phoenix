defmodule Escalated.Services.TicketSubjectServiceTest do
  # credo:disable-for-this-file
  use ExUnit.Case, async: false
  use Escalated.DataCase

  alias Escalated.Services.{TicketService, TicketSubjectService}
  alias Escalated.Serializers.TicketSerializer
  alias Escalated.Test.{FakeProject, FakeProjectStore}

  setup do
    prev = Application.get_env(:escalated, :ticket_subjects)

    Application.put_env(:escalated, :ticket_subjects,
      types: ["project"],
      resolver: fn "project", id -> FakeProjectStore.get(id) end
    )

    FakeProjectStore.reset!()

    on_exit(fn -> Application.put_env(:escalated, :ticket_subjects, prev) end)

    :ok
  end

  defp create_ticket! do
    {:ok, ticket} =
      TicketService.create(%{subject: "Help", description: "Need assistance", channel: "web"})

    ticket
  end

  test "attaches a host subject preserving a string key" do
    ticket = create_ticket!()
    FakeProjectStore.put(%FakeProject{id: "prj_9f1c", name: "Acme Redesign", account: "Acme"})

    assert {:ok, link} =
             TicketSubjectService.attach_subject(ticket, "project", "prj_9f1c", role: "project")

    assert link.subject_type == "project"
    assert link.subject_id == "prj_9f1c"
    assert link.role == "project"
    assert length(TicketSubjectService.list(ticket)) == 1
  end

  test "is idempotent on ticket+type+id and updates role" do
    ticket = create_ticket!()
    FakeProjectStore.put(%FakeProject{id: "p1", name: "A", account: nil})

    assert {:ok, _} = TicketSubjectService.attach_subject(ticket, "project", "p1")

    assert {:ok, link} =
             TicketSubjectService.attach_subject(ticket, "project", "p1", role: "account")

    assert length(TicketSubjectService.list(ticket)) == 1
    assert link.role == "account"
  end

  test "detaches a subject" do
    ticket = create_ticket!()
    FakeProjectStore.put(%FakeProject{id: "1", name: "A", account: nil})
    {:ok, _} = TicketSubjectService.attach_subject(ticket, "project", "1")

    assert {:ok, 1} = TicketSubjectService.detach_subject(ticket, "project", "1")
    assert TicketSubjectService.list(ticket) == []
  end

  test "syncs subjects replacing existing and preserving order" do
    ticket = create_ticket!()

    FakeProjectStore.put(%FakeProject{id: "a", name: "A", account: nil})
    FakeProjectStore.put(%FakeProject{id: "b", name: "B", account: nil})
    FakeProjectStore.put(%FakeProject{id: "c", name: "C", account: nil})

    {:ok, _} = TicketSubjectService.attach_subject(ticket, "project", "a")

    assert {:ok, links} =
             TicketSubjectService.sync_subjects(ticket, [
               {"project", "b", "primary"},
               {"project", "c"}
             ])

    assert length(links) == 2
    assert Enum.at(links, 0).subject_id == "b"
    assert Enum.at(links, 0).role == "primary"
    assert Enum.at(links, 0).position == 0
    assert Enum.at(links, 1).subject_id == "c"
    assert Enum.at(links, 1).position == 1
  end

  test "rejects attaching a type outside the configured allowlist" do
    Application.put_env(:escalated, :ticket_subjects,
      types: ["customer"],
      resolver: fn _, _ -> nil end
    )

    ticket = create_ticket!()

    assert_raise ArgumentError, ~r/not an allowed ticket subject/, fn ->
      TicketSubjectService.attach_subject(ticket, "project", "1")
    end
  end

  test "allows any type programmatically when allowlist is empty" do
    Application.put_env(:escalated, :ticket_subjects, types: [], resolver: fn _, _ -> nil end)
    ticket = create_ticket!()

    assert {:ok, _} = TicketSubjectService.attach_subject(ticket, "project", "1")
  end

  test "serializes subjects on ticket detail via TicketSerializer" do
    ticket = create_ticket!()

    FakeProjectStore.put(%FakeProject{id: "7", name: "Acme Redesign", account: "Acme"})

    {:ok, _} = TicketSubjectService.attach_subject(ticket, "project", "7", role: "project")

    subjects = TicketSerializer.subjects(ticket)

    assert [
             %{
               type: "project",
               id: "7",
               role: "project",
               title: "Acme Redesign",
               subtitle: "Project · Acme",
               url: "https://app.test/projects/7",
               color: "#2563eb",
               icon: "folder",
               missing: false
             }
           ] = subjects
  end
end
