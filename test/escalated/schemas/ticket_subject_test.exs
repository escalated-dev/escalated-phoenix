defmodule Escalated.Schemas.TicketSubjectTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.TicketSubject

  test "valid changeset" do
    changeset =
      TicketSubject.changeset(%TicketSubject{}, %{
        ticket_id: 1,
        subject_type: "project",
        subject_id: "prj_1",
        role: "project",
        position: 0
      })

    assert changeset.valid?
  end

  test "requires ticket_id, subject_type, and subject_id" do
    changeset = TicketSubject.changeset(%TicketSubject{}, %{})
    refute changeset.valid?
    assert %{ticket_id: _, subject_type: _, subject_id: _} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
