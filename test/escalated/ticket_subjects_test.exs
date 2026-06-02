defmodule Escalated.TicketSubjectsTest do
  # credo:disable-for-this-file
  use ExUnit.Case, async: false

  alias Escalated.Schemas.TicketSubject
  alias Escalated.TicketSubjects
  alias Escalated.Test.FakeProject

  describe "allowed_types/0" do
    test "flattens list entries" do
      prev = Application.get_env(:escalated, :ticket_subjects)
      Application.put_env(:escalated, :ticket_subjects, types: ["project", "customer"])

      on_exit(fn -> Application.put_env(:escalated, :ticket_subjects, prev) end)

      assert TicketSubjects.allowed_types() == ["project", "customer"]
    end

    test "flattens map alias entries" do
      prev = Application.get_env(:escalated, :ticket_subjects)

      Application.put_env(:escalated, :ticket_subjects,
        types: %{"project" => "App.Project", "customer" => "App.Customer"}
      )

      on_exit(fn -> Application.put_env(:escalated, :ticket_subjects, prev) end)

      assert "project" in TicketSubjects.allowed_types()
      assert "App.Project" in TicketSubjects.allowed_types()
    end
  end

  describe "type_allowed?/1 and api_type_allowed?/1" do
    test "empty allowlist permits any type programmatically but not via API" do
      prev = Application.get_env(:escalated, :ticket_subjects)
      Application.put_env(:escalated, :ticket_subjects, types: [])
      on_exit(fn -> Application.put_env(:escalated, :ticket_subjects, prev) end)

      assert TicketSubjects.type_allowed?("anything")
      refute TicketSubjects.api_type_allowed?("anything")
    end
  end

  describe "serialize_links/1" do
    test "serializes through the presentation behaviour" do
      prev = Application.get_env(:escalated, :ticket_subjects)

      Application.put_env(:escalated, :ticket_subjects,
        resolver: fn "project", "7" ->
          %FakeProject{id: "7", name: "Acme Redesign", account: "Acme"}
        end
      )

      on_exit(fn -> Application.put_env(:escalated, :ticket_subjects, prev) end)

      link = %TicketSubject{
        subject_type: "project",
        subject_id: "7",
        role: "project",
        position: 0
      }

      assert [subject] = TicketSubjects.serialize_links([link])

      assert subject == %{
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
    end

    test "falls back to type#id when subject is missing" do
      prev = Application.get_env(:escalated, :ticket_subjects)
      Application.put_env(:escalated, :ticket_subjects, resolver: fn _, _ -> nil end)
      on_exit(fn -> Application.put_env(:escalated, :ticket_subjects, prev) end)

      link = %TicketSubject{subject_type: "project", subject_id: "99", role: nil, position: 0}
      assert [%{title: "project #99", missing: true}] = TicketSubjects.serialize_links([link])
    end
  end
end
