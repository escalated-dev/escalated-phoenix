defmodule Escalated.Controllers.CustomFieldPagesTest do
  @moduledoc """
  `Escalated/Admin/CustomFields/{Index,Form}` and
  `Escalated/Admin/CustomObjects/{Index,Form,Records}` against the props the
  shared Vue pages read and the routes they post to (escalated-laravel's
  `Admin\\CustomFieldController` and `Admin\\CustomObjectController`).
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{CustomField, CustomFieldValue, CustomObject, CustomObjectRecord}

  defp repo, do: Escalated.repo()

  @field_keys ~w(id name slug type context options required placeholder description
                 validation_rules conditions position active created_at updated_at)
  @object_keys ~w(id name slug fields_schema records_count created_at updated_at)
  @record_keys ~w(id object_id data created_at updated_at)

  @schema [
    %{"name" => "Plan", "type" => "select", "required" => true, "options" => ["Free", "Pro"]},
    %{"name" => "Seats", "type" => "number"},
    %{"name" => "Renews", "type" => "date"},
    %{"name" => "Notes", "type" => "text"}
  ]

  setup do
    %{
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      agent: host_user!(%{name: "Al Agent", is_agent: true})
    }
  end

  defp field!(attrs) do
    %CustomField{}
    |> CustomField.changeset(Map.merge(%{name: "Order number", field_type: "text"}, attrs))
    |> repo().insert!()
  end

  defp object!(attrs \\ %{}) do
    %CustomObject{}
    |> CustomObject.changeset(
      Map.merge(%{name: "Contracts", slug: "contracts", fields_schema: @schema}, attrs)
    )
    |> repo().insert!()
  end

  defp record!(object, data) do
    %CustomObjectRecord{}
    |> CustomObjectRecord.changeset(%{custom_object_id: object.id, data: data})
    |> repo().insert!()
  end

  defp field_body(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Order Number",
        "type" => "text",
        "context" => "ticket",
        "options" => [],
        "required" => true,
        "placeholder" => "ORD-1234",
        "description" => "From the receipt",
        "position" => 3,
        "active" => true
      },
      overrides
    )
  end

  defp errors(conn) do
    assert conn.status in [302, 303, 422], "expected a validation answer, got #{conn.status}"

    case conn.status do
      422 ->
        Jason.decode!(conn.resp_body)["errors"]

      _ ->
        conn |> Plug.Conn.fetch_session() |> Plug.Conn.get_session("inertia_errors") || %{}
    end
  end

  defp json_errors(method, path, user, body) do
    conn =
      conn(method, path, Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> init_test_session(%{})
      |> assign(:current_user, user)
      |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))

    assert conn.status == 422, "expected 422, got #{conn.status}: #{conn.resp_body}"
    Jason.decode!(conn.resp_body)["errors"]
  end

  describe "Escalated/Admin/CustomFields/Index" do
    test "lists every field ordered by position with Laravel's keys", %{admin: admin} do
      second = field!(%{name: "Second", position: 2, field_type: "select", options: ["a"]})
      first = field!(%{name: "First", position: 1, is_required: true, entity_type: "user"})

      props =
        visit(:get, "/support/admin/custom-fields", admin)
        |> page!("Escalated/Admin/CustomFields/Index")

      assert [row1, row2] = props["fields"]
      assert_keys(row1, @field_keys, "field")
      assert row1["id"] == first.id
      assert row1["name"] == "First"
      assert row1["type"] == "text"
      assert row1["context"] == "user"
      assert row1["required"] == true
      assert row1["active"] == true
      assert row1["position"] == 1
      assert row2["id"] == second.id
      assert row2["type"] == "select"
      assert row2["options"] == ["a"]
    end

    test "is admin only", %{agent: agent} do
      assert visit(:get, "/support/admin/custom-fields", agent).status == 403
    end
  end

  describe "Escalated/Admin/CustomFields/Form" do
    test "create sends the contexts", %{admin: admin} do
      props =
        visit(:get, "/support/admin/custom-fields/create", admin)
        |> page!("Escalated/Admin/CustomFields/Form")

      assert props["contexts"] == ["ticket", "user", "organization"]
      refute Map.has_key?(props, "field")
    end

    test "edit sends the field and the contexts", %{admin: admin} do
      field = field!(%{placeholder: "ORD-1"})

      props =
        visit(:get, "/support/admin/custom-fields/#{field.id}/edit", admin)
        |> page!("Escalated/Admin/CustomFields/Form")

      assert_keys(props, ~w(field contexts))
      assert_keys(props["field"], @field_keys, "field")
      assert props["field"]["id"] == field.id
      assert props["field"]["placeholder"] == "ORD-1"
    end

    test "edit of an unknown field is a 404", %{admin: admin} do
      assert visit(:get, "/support/admin/custom-fields/999999/edit", admin).status == 404
    end
  end

  describe "custom field writes" do
    test "store creates the field and generates an underscore slug", %{admin: admin} do
      conn = visit(:post, "/support/admin/custom-fields", admin, field_body())

      assert conn.status in [302, 303]
      assert location(conn) == "/support/admin/custom-fields"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Custom field created."

      field = repo().one!(CustomField)
      assert field.slug == "order_number"
      assert field.field_type == "text"
      assert field.entity_type == "ticket"
      assert field.is_required == true
      assert field.is_active == true
      assert field.placeholder == "ORD-1234"
      assert field.description == "From the receipt"
      assert field.position == 3
    end

    test "store de-duplicates the slug with _2, _3", %{admin: admin} do
      for _ <- 1..3, do: visit(:post, "/support/admin/custom-fields", admin, field_body())

      slugs = repo().all(from(f in CustomField, order_by: f.id, select: f.slug))
      assert slugs == ["order_number", "order_number_2", "order_number_3"]
    end

    test "store validates name, type and context", %{admin: admin} do
      errors =
        visit(
          :post,
          "/support/admin/custom-fields",
          admin,
          field_body(%{"name" => "", "type" => "url", "context" => "planet"})
        )
        |> errors()

      assert Map.has_key?(errors, "name")
      assert Map.has_key?(errors, "type")
      assert Map.has_key?(errors, "context")
      assert repo().aggregate(CustomField, :count) == 0
    end

    test "select and multi_select need at least one option", %{admin: admin} do
      for type <- ~w(select multi_select) do
        errors =
          json_errors(
            :post,
            "/support/admin/custom-fields",
            admin,
            field_body(%{"type" => type, "options" => []})
          )

        assert Map.has_key?(errors, "options")
      end

      assert repo().aggregate(CustomField, :count) == 0

      conn =
        visit(
          :post,
          "/support/admin/custom-fields",
          admin,
          field_body(%{"type" => "select", "options" => ["Low", "High"]})
        )

      assert conn.status in [302, 303]
      assert repo().one!(CustomField).options == ["Low", "High"]
    end

    test "update changes the field and keeps its slug", %{admin: admin} do
      field = field!(%{name: "Order number"})

      conn =
        visit(
          :put,
          "/support/admin/custom-fields/#{field.id}",
          admin,
          field_body(%{"name" => "Receipt", "required" => false, "active" => false})
        )

      assert conn.status in [302, 303]
      assert location(conn) == "/support/admin/custom-fields"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Custom field updated."

      updated = repo().get!(CustomField, field.id)
      assert updated.name == "Receipt"
      assert updated.slug == field.slug
      refute updated.is_required
      refute updated.is_active
    end

    test "destroy deletes the field and its values", %{admin: admin} do
      field = field!(%{})

      repo().insert!(
        CustomFieldValue.changeset(%CustomFieldValue{}, %{
          custom_field_id: field.id,
          entity_type: "ticket",
          entity_id: 1,
          value: "x"
        })
      )

      conn = visit(:delete, "/support/admin/custom-fields/#{field.id}", admin)

      assert conn.status in [302, 303]
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Custom field deleted."
      assert repo().aggregate(CustomField, :count) == 0
      assert repo().aggregate(CustomFieldValue, :count) == 0
    end

    test "reorder sets the positions", %{admin: admin} do
      a = field!(%{name: "A", position: 0})
      b = field!(%{name: "B", position: 1})

      conn =
        visit(:post, "/support/admin/custom-fields/reorder", admin, %{
          "positions" => [%{"id" => a.id, "position" => 5}, %{"id" => b.id, "position" => 2}]
        })

      assert conn.status in [302, 303]
      assert repo().get!(CustomField, a.id).position == 5
      assert repo().get!(CustomField, b.id).position == 2
    end

    test "reorder rejects unknown ids", %{admin: admin} do
      errors =
        json_errors(:post, "/support/admin/custom-fields/reorder", admin, %{
          "positions" => [%{"id" => 999_999, "position" => 1}]
        })

      assert errors != %{}
    end

    test "writes are admin only", %{agent: agent} do
      assert visit(:post, "/support/admin/custom-fields", agent, field_body()).status == 403
      assert repo().aggregate(CustomField, :count) == 0
    end
  end

  describe "Escalated/Admin/CustomObjects/Index" do
    test "lists objects by name with their record counts", %{admin: admin} do
      contracts = object!()
      assets = object!(%{name: "Assets", slug: "assets"})
      record!(contracts, %{"Plan" => "Pro"})
      record!(contracts, %{"Plan" => "Free"})

      props =
        visit(:get, "/support/admin/custom-objects", admin)
        |> page!("Escalated/Admin/CustomObjects/Index")

      assert [first, second] = props["objects"]
      assert_keys(first, @object_keys, "object")
      assert first["id"] == assets.id
      assert first["records_count"] == 0
      assert second["id"] == contracts.id
      assert second["slug"] == "contracts"
      assert second["records_count"] == 2
      assert [%{"name" => "Plan", "type" => "select"} | _] = second["fields_schema"]
    end
  end

  describe "Escalated/Admin/CustomObjects/Form" do
    test "create renders the empty form", %{admin: admin} do
      props =
        visit(:get, "/support/admin/custom-objects/create", admin)
        |> page!("Escalated/Admin/CustomObjects/Form")

      assert props["object"] == nil
    end

    test "edit sends the object", %{admin: admin} do
      object = object!()

      props =
        visit(:get, "/support/admin/custom-objects/#{object.id}/edit", admin)
        |> page!("Escalated/Admin/CustomObjects/Form")

      assert_keys(props["object"], ~w(id name slug fields_schema), "object")
      assert props["object"]["fields_schema"] |> length() == 4
    end
  end

  describe "custom object writes" do
    test "store creates the object", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/custom-objects", admin, %{
          "name" => "Contracts",
          "slug" => "contracts",
          "fields_schema" => @schema
        })

      assert conn.status in [302, 303]
      assert location(conn) == "/support/admin/custom-objects"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Custom object created."

      object = repo().one!(CustomObject)
      assert object.slug == "contracts"
      assert [%{"name" => "Plan", "type" => "select"} | _] = object.fields_schema
    end

    test "store validates the slug and schema", %{admin: admin} do
      object!()

      errors =
        json_errors(:post, "/support/admin/custom-objects", admin, %{
          "name" => "Again",
          "slug" => "contracts",
          "fields_schema" => @schema
        })

      assert Map.has_key?(errors, "slug")

      errors =
        json_errors(:post, "/support/admin/custom-objects", admin, %{
          "name" => "",
          "slug" => "not a slug!",
          "fields_schema" => []
        })

      assert Map.has_key?(errors, "name")
      assert Map.has_key?(errors, "slug")
      assert Map.has_key?(errors, "fields_schema")

      errors =
        json_errors(:post, "/support/admin/custom-objects", admin, %{
          "name" => "Bad",
          "slug" => "bad",
          "fields_schema" => [%{"name" => "", "type" => "colour"}]
        })

      assert Map.has_key?(errors, "fields_schema.0.name")
      assert Map.has_key?(errors, "fields_schema.0.type")
      assert repo().aggregate(CustomObject, :count) == 1
    end

    test "update keeps its own slug and changes the schema", %{admin: admin} do
      object = object!()

      conn =
        visit(:put, "/support/admin/custom-objects/#{object.id}", admin, %{
          "name" => "Agreements",
          "slug" => "contracts",
          "fields_schema" => [%{"name" => "Owner", "type" => "text"}]
        })

      assert conn.status in [302, 303]
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Custom object updated."
      updated = repo().get!(CustomObject, object.id)
      assert updated.name == "Agreements"
      assert updated.fields_schema == [%{"name" => "Owner", "type" => "text"}]
    end

    test "destroy deletes the object and its records", %{admin: admin} do
      object = object!()
      record!(object, %{"Plan" => "Pro"})

      conn = visit(:delete, "/support/admin/custom-objects/#{object.id}", admin)

      assert conn.status in [302, 303]
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Custom object deleted."
      assert repo().aggregate(CustomObject, :count) == 0
      assert repo().aggregate(CustomObjectRecord, :count) == 0
    end
  end

  describe "Escalated/Admin/CustomObjects/Records" do
    test "sends the object and its records, newest first", %{admin: admin} do
      object = object!()
      older = record!(object, %{"Plan" => "Free"})
      newer = record!(object, %{"Plan" => "Pro", "Seats" => "5"})

      props =
        visit(:get, "/support/admin/custom-objects/#{object.id}/records", admin)
        |> page!("Escalated/Admin/CustomObjects/Records")

      assert_keys(props, ~w(object records))
      assert_keys(props["object"], ~w(id name fields_schema), "object")
      assert [first, second] = props["records"]
      assert_keys(first, @record_keys, "record")
      assert first["id"] == newer.id
      assert first["object_id"] == object.id
      assert first["data"] == %{"Plan" => "Pro", "Seats" => "5"}
      assert second["id"] == older.id
    end

    test "store, update and destroy a record", %{admin: admin} do
      object = object!()
      path = "/support/admin/custom-objects/#{object.id}/records"

      conn =
        visit(:post, path, admin, %{
          "data" => %{"Plan" => "Pro", "Seats" => "10", "Renews" => "2027-01-31", "Notes" => ""}
        })

      assert conn.status in [302, 303]
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Record created."
      record = repo().one!(CustomObjectRecord)
      assert record.data["Plan"] == "Pro"

      conn = visit(:put, "#{path}/#{record.id}", admin, %{"data" => %{"Plan" => "Free"}})
      assert conn.status in [302, 303]
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Record updated."
      assert repo().get!(CustomObjectRecord, record.id).data == %{"Plan" => "Free"}

      conn = visit(:delete, "#{path}/#{record.id}", admin)
      assert conn.status in [302, 303]
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Record deleted."
      assert repo().aggregate(CustomObjectRecord, :count) == 0
    end

    test "record data is validated against the schema", %{admin: admin} do
      object = object!()
      path = "/support/admin/custom-objects/#{object.id}/records"

      errors =
        json_errors(:post, path, admin, %{
          "data" => %{
            "Plan" => "Enterprise",
            "Seats" => "many",
            "Renews" => "2027-02-30",
            "Colour" => "red"
          }
        })

      assert Map.has_key?(errors, "data.Plan")
      assert Map.has_key?(errors, "data.Seats")
      assert Map.has_key?(errors, "data.Renews")
      assert Map.has_key?(errors, "data.Colour")

      errors = json_errors(:post, path, admin, %{"data" => %{"Seats" => "3"}})
      assert Map.has_key?(errors, "data.Plan")

      errors = json_errors(:post, path, admin, %{"data" => "nope"})
      assert Map.has_key?(errors, "data")

      assert repo().aggregate(CustomObjectRecord, :count) == 0
    end

    test "a record of another object is a 404", %{admin: admin} do
      object = object!()
      other = object!(%{name: "Other", slug: "other"})
      record = record!(other, %{"Plan" => "Pro"})
      path = "/support/admin/custom-objects/#{object.id}/records/#{record.id}"

      assert visit(:put, path, admin, %{"data" => %{"Plan" => "Free"}}).status == 404
      assert visit(:delete, path, admin).status == 404
      assert repo().get!(CustomObjectRecord, record.id).data == %{"Plan" => "Pro"}
    end
  end
end
