defmodule Escalated.Schemas.ContactTest do
  use ExUnit.Case, async: true
  alias Escalated.Schemas.Contact

  # --------------------------------------------------------------------
  # normalize_email/1 (pure)
  # --------------------------------------------------------------------

  describe "normalize_email/1" do
    test "lowercases" do
      assert Contact.normalize_email("ALICE@Example.COM") == "alice@example.com"
    end

    test "trims surrounding whitespace" do
      assert Contact.normalize_email("  alice@example.com  ") == "alice@example.com"
    end

    test "does both in one pass" do
      assert Contact.normalize_email("  MiXeD@Case.COM  ") == "mixed@case.com"
    end

    test "returns empty string for nil" do
      assert Contact.normalize_email(nil) == ""
    end
  end

  # --------------------------------------------------------------------
  # decide_action/2 (pure)
  # --------------------------------------------------------------------

  describe "decide_action/2" do
    test "returns :create when no existing row" do
      assert Contact.decide_action(nil, "Alice") == :create
    end

    test "returns :return_existing when existing has non-blank name" do
      existing = %{name: "Alice"}
      assert Contact.decide_action(existing, "Different") == :return_existing
    end

    test "returns :update_name when existing name is blank and a name is supplied" do
      assert Contact.decide_action(%{name: nil}, "Alice") == :update_name
      assert Contact.decide_action(%{name: ""}, "Alice") == :update_name
    end

    test "returns :return_existing when existing name is blank but no incoming name" do
      assert Contact.decide_action(%{name: nil}, nil) == :return_existing
      assert Contact.decide_action(%{name: nil}, "") == :return_existing
    end
  end

  # --------------------------------------------------------------------
  # changeset
  # --------------------------------------------------------------------

  describe "changeset/2" do
    test "requires email" do
      changeset = Contact.changeset(%Contact{}, %{})
      refute changeset.valid?
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "normalizes email on update_change" do
      changeset = Contact.changeset(%Contact{}, %{email: "  UPPER@Case.COM "})
      assert changeset.changes.email == "upper@case.com"
    end

    test "accepts optional name and metadata" do
      changeset =
        Contact.changeset(%Contact{}, %{
          email: "alice@example.com",
          name: "Alice",
          metadata: %{"source" => "widget"}
        })

      assert changeset.valid?
    end
  end

  # -------------------------------------------------------------------
  # Wire-up — verifies TicketService.create resolves a Contact from
  # guest_email. Tagged :integration so projects without a DB-backed
  # test harness can skip it.
  # -------------------------------------------------------------------

  describe "TicketService.create wire-up" do
    @describetag :integration

    setup _ do
      Escalated.DataCase.setup_sandbox(%{async: false})
      :ok
    end

    test "with guest_email dedupes repeat submitters onto one Contact" do
      attrs1 = %{
        subject: "First",
        description: "body",
        guest_name: "Alice",
        guest_email: "alice@example.com",
        channel: "web"
      }

      attrs2 = %{
        subject: "Second",
        description: "body",
        guest_name: "Alice",
        guest_email: "ALICE@Example.COM",
        channel: "web"
      }

      {:ok, t1} = Escalated.Services.TicketService.create(attrs1)
      {:ok, t2} = Escalated.Services.TicketService.create(attrs2)
      assert t1.contact_id == t2.contact_id
      refute is_nil(t1.contact_id)
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
