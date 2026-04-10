defmodule Escalated.Schemas.CustomFieldTest do
  use ExUnit.Case, async: true
  alias Escalated.Schemas.CustomField

  test "changeset validates field_type inclusion" do
    changeset = CustomField.changeset(%CustomField{}, %{name: "Test", field_type: "invalid"})
    refute changeset.valid?
  end

  test "changeset accepts valid field types" do
    for type <- CustomField.field_types() do
      changeset = CustomField.changeset(%CustomField{}, %{name: "Test", field_type: type})
      assert changeset.valid?, "Expected #{type} to be valid"
    end
  end

  test "changeset auto-generates slug from name" do
    changeset = CustomField.changeset(%CustomField{}, %{name: "My Custom Field", field_type: "text"})
    assert Ecto.Changeset.get_field(changeset, :slug) == "my-custom-field"
  end

  test "field_types returns all expected types" do
    types = CustomField.field_types()
    assert "text" in types
    assert "select" in types
    assert "checkbox" in types
    assert "date" in types
    assert length(types) == 8
  end
end
