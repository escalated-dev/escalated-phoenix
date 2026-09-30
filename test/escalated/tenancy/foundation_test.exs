defmodule Escalated.Tenancy.FoundationTest do
  use Escalated.DataCase, async: true

  alias Escalated.Schemas.{AgentProfile, Contact, EscalatedSetting, Role}
  alias Escalated.Tenancy.Tables
  alias Escalated.TestRepo

  test "the ownership registry covers every package schema and every reference field exists" do
    package_schemas =
      :escalated
      |> Application.spec(:modules)
      |> Enum.filter(fn module ->
        String.starts_with?(Atom.to_string(module), "Elixir.Escalated.Schemas.") and
          module != Escalated.Schemas.GuestMailboxBudget and
          Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1)
      end)

    entries = Tables.entries()
    assert MapSet.new(Enum.map(entries, & &1.schema)) == MapSet.new(package_schemas)
    assert length(entries) == MapSet.size(MapSet.new(Enum.map(entries, & &1.name)))

    by_name = Map.new(entries, &{&1.name, &1})

    for entry <- entries do
      schema = entry.schema
      assert schema.__schema__(:source) == Escalated.table_name(entry.name)
      assert schema.__schema__(:type, :tenant_id) == :string
      assert struct(schema).tenant_id == ""

      for {field, {parent_name, parent_key}} <- entry.local_refs do
        assert field in schema.__schema__(:fields)
        assert parent_key in by_name[parent_name].schema.__schema__(:fields)
      end

      for field <- entry.host_refs ++ Map.get(entry, :host_ref_lists, []) do
        assert field in schema.__schema__(:fields)
      end

      for {id_field, type_field} <- Map.get(entry, :polymorphic_refs, %{}) do
        assert id_field in schema.__schema__(:fields)
        assert type_field in schema.__schema__(:fields)
      end

      for fields <- entry.unique_keys, field <- fields do
        assert field in schema.__schema__(:fields)
      end
    end
  end

  test "the legacy namespace and case-sensitive merchant namespaces can share a contact email" do
    for tenant <- ["", "Merchant", "merchant"] do
      assert {:ok, contact} =
               %Contact{tenant_id: tenant}
               |> Contact.changeset(%{email: "recipient@example.com"})
               |> TestRepo.insert()

      assert contact.tenant_id == tenant
    end

    assert {:error, changeset} =
             %Contact{tenant_id: "Merchant"}
             |> Contact.changeset(%{email: "recipient@example.com"})
             |> TestRepo.insert()

    assert {_, options} = changeset.errors[:email]
    assert options[:constraint] == :unique
  end

  test "tenant-local settings, roles and staff profiles retain their changeset constraints" do
    user_id =
      case AgentProfile.__schema__(:type, :user_id) do
        :binary_id -> Ecto.UUID.generate()
        :string -> "merchant-staff"
        _ -> 321
      end

    for {schema, attrs, unique_field} <- [
          {EscalatedSetting, %{key: "support_email", value: "help@example.com"}, :key},
          {Role, %{name: "Support", slug: "support"}, :slug},
          {AgentProfile, %{user_id: user_id, role: "agent"}, :user_id}
        ] do
      for tenant <- ["merchant-a", "merchant-b"] do
        assert {:ok, record} =
                 schema
                 |> struct(tenant_id: tenant)
                 |> schema.changeset(attrs)
                 |> TestRepo.insert()

        assert record.tenant_id == tenant
      end

      assert {:error, changeset} =
               schema
               |> struct(tenant_id: "merchant-a")
               |> schema.changeset(attrs)
               |> TestRepo.insert()

      assert {_, options} = changeset.errors[unique_field]
      assert options[:constraint] == :unique
    end
  end
end
