defmodule Escalated.Controllers.Admin.CustomObjectController do
  @moduledoc """
  Admin CRUD over custom objects and their records, serving
  `Escalated/Admin/CustomObjects/Index`, `Form` and `Records` with the props
  escalated-laravel's `Admin\\CustomObjectController` sends.

  A record's `data` is checked against its object's `fields_schema`: required
  keys non-empty, `number` numeric, `date` a valid `YYYY-MM-DD`, `select` one
  of the options, and no keys the schema does not name. Errors are keyed
  `data.<name>`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{CustomObject, CustomObjectRecord}

  @schema_types ~w(text number select date lookup)

  def index(conn, _params) do
    objects = from(o in CustomObject, order_by: [asc: o.name, asc: o.id]) |> repo().all()

    counts =
      from(r in CustomObjectRecord,
        group_by: r.custom_object_id,
        select: {r.custom_object_id, count(r.id)}
      )
      |> repo().all()
      |> Map.new()

    rows =
      Enum.map(objects, fn o ->
        o |> object_json() |> Map.put(:records_count, Map.get(counts, o.id, 0))
      end)

    UIRenderer.render_page(conn, "Escalated/Admin/CustomObjects/Index", %{objects: rows})
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/CustomObjects/Form", %{object: nil})
  end

  def edit(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      object ->
        UIRenderer.render_page(conn, "Escalated/Admin/CustomObjects/Form", %{
          object: object_json(object)
        })
    end
  end

  def create(conn, params) do
    with {:ok, attrs} <- object_attrs(params, nil),
         {:ok, _} <- %CustomObject{} |> CustomObject.changeset(attrs) |> repo().insert() do
      conn |> put_flash(:info, "Custom object created.") |> redirect(to: index_path())
    else
      {:error, errors} -> FormResponse.invalid(conn, errors, index_path() <> "/create")
    end
  end

  def update(conn, %{"id" => id} = params) do
    with object when not is_nil(object) <- find(id),
         {:ok, attrs} <- object_attrs(params, object.id),
         {:ok, _} <- object |> CustomObject.changeset(attrs) |> repo().update() do
      conn |> put_flash(:info, "Custom object updated.") |> redirect(to: index_path())
    else
      nil -> not_found(conn)
      {:error, errors} -> FormResponse.invalid(conn, errors, "#{index_path()}/#{id}/edit")
    end
  end

  def delete(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      object ->
        # Records go with it (ON DELETE CASCADE, and explicitly for databases
        # that do not enforce foreign keys).
        repo().transaction(fn ->
          from(r in CustomObjectRecord, where: r.custom_object_id == ^object.id)
          |> repo().delete_all()

          repo().delete!(object)
        end)

        conn |> put_flash(:info, "Custom object deleted.") |> redirect(to: index_path())
    end
  end

  def records(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      object ->
        records =
          from(r in CustomObjectRecord,
            where: r.custom_object_id == ^object.id,
            order_by: [desc: r.id]
          )
          |> repo().all()
          |> Enum.map(&record_json/1)

        UIRenderer.render_page(conn, "Escalated/Admin/CustomObjects/Records", %{
          object: object_json(object),
          records: records
        })
    end
  end

  def create_record(conn, %{"id" => id} = params) do
    case find(id) do
      nil ->
        not_found(conn)

      object ->
        with {:ok, data} <- record_data(object, params["data"]),
             {:ok, _} <-
               %CustomObjectRecord{}
               |> CustomObjectRecord.changeset(%{custom_object_id: object.id, data: data})
               |> repo().insert() do
          conn |> put_flash(:info, "Record created.") |> redirect(to: records_path(conn, object))
        else
          {:error, errors} -> FormResponse.invalid(conn, errors, records_path(conn, object))
        end
    end
  end

  def update_record(conn, %{"id" => id, "record_id" => record_id} = params) do
    with object when not is_nil(object) <- find(id),
         record when not is_nil(record) <- find_record(object, record_id) do
      with {:ok, data} <- record_data(object, params["data"]),
           {:ok, _} <- record |> CustomObjectRecord.changeset(%{data: data}) |> repo().update() do
        conn |> put_flash(:info, "Record updated.") |> redirect(to: records_path(conn, object))
      else
        {:error, errors} -> FormResponse.invalid(conn, errors, records_path(conn, object))
      end
    else
      nil -> not_found(conn)
    end
  end

  def delete_record(conn, %{"id" => id, "record_id" => record_id}) do
    with object when not is_nil(object) <- find(id),
         record when not is_nil(record) <- find_record(object, record_id) do
      repo().delete!(record)
      conn |> put_flash(:info, "Record deleted.") |> redirect(to: records_path(conn, object))
    else
      nil -> not_found(conn)
    end
  end

  # Private

  # Laravel's rules: name required (max 255); slug required, max 100,
  # alpha-dash and unique; fields_schema at least one field, each with a name
  # (max 100) and a type from the list.
  defp object_attrs(params, own_id) do
    name = trimmed(params["name"])
    slug = trimmed(params["slug"])
    schema = params["fields_schema"]

    errors =
      %{}
      |> put_if(name in [nil, ""], "name", "The name field is required.")
      |> put_if(
        is_binary(name) and String.length(name) > 255,
        "name",
        "The name may not be greater than 255 characters."
      )
      |> put_if(slug in [nil, ""], "slug", "The slug field is required.")
      |> put_if(
        is_binary(slug) and String.length(slug) > 100,
        "slug",
        "The slug may not be greater than 100 characters."
      )
      |> put_if(
        is_binary(slug) and slug != "" and not Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, slug),
        "slug",
        "The slug may only contain letters, numbers, dashes and underscores."
      )
      |> put_if(slug_taken?(slug, own_id), "slug", "The slug has already been taken.")
      |> put_if(
        not is_list(schema) or schema == [],
        "fields_schema",
        "The fields schema must have at least 1 field."
      )
      |> Map.merge(schema_errors(schema))

    if errors == %{} do
      {:ok, %{name: name, slug: slug, fields_schema: Enum.map(schema, &schema_field/1)}}
    else
      {:error, errors}
    end
  end

  defp schema_errors(schema) when is_list(schema) do
    schema
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn
      {%{} = field, i}, acc ->
        name = field["name"]

        acc
        |> put_if(
          not is_binary(name) or String.trim(name) == "",
          "fields_schema.#{i}.name",
          "The field name is required."
        )
        |> put_if(
          is_binary(name) and String.length(name) > 100,
          "fields_schema.#{i}.name",
          "The field name may not be greater than 100 characters."
        )
        |> put_if(
          field["type"] not in @schema_types,
          "fields_schema.#{i}.type",
          "The selected type is invalid."
        )
        |> put_if(
          Map.has_key?(field, "required") and not is_boolean(field["required"]),
          "fields_schema.#{i}.required",
          "The required flag must be true or false."
        )
        |> put_if(
          Map.has_key?(field, "options") and not is_list(field["options"]),
          "fields_schema.#{i}.options",
          "The options must be an array."
        )

      {_, i}, acc ->
        Map.put(acc, "fields_schema.#{i}", ["Each field must be an object."])
    end)
  end

  defp schema_errors(_), do: %{}

  defp schema_field(field) do
    field
    |> Map.take(~w(name type required options))
    |> Map.update!("name", &String.trim/1)
  end

  defp slug_taken?(slug, _own_id) when slug in [nil, ""], do: false

  defp slug_taken?(slug, own_id) do
    query = from(o in CustomObject, where: o.slug == ^slug, select: o.id)
    Enum.any?(repo().all(query), &(&1 != own_id))
  end

  defp record_data(object, data) when is_map(data) do
    schema = object.fields_schema || []
    names = Enum.map(schema, & &1["name"])

    unknown =
      data
      |> Map.keys()
      |> Enum.reject(&(&1 in names))
      |> Map.new(&{"data.#{&1}", ["is not a field of #{object.name}"]})

    errors =
      Enum.reduce(schema, unknown, fn field, acc ->
        case check_record_value(field, Map.get(data, field["name"])) do
          :ok -> acc
          {:error, message} -> Map.put(acc, "data.#{field["name"]}", [message])
        end
      end)

    if errors == %{}, do: {:ok, data}, else: {:error, errors}
  end

  defp record_data(_object, _data), do: {:error, %{"data" => ["The data field is required."]}}

  defp check_record_value(field, value) do
    name = field["name"]

    cond do
      blank?(value) and field["required"] == true -> {:error, "The #{name} field is required."}
      blank?(value) -> :ok
      true -> check_typed(field, value)
    end
  end

  defp check_typed(%{"type" => "number", "name" => name}, value) do
    if number?(value), do: :ok, else: {:error, "The #{name} field must be a number."}
  end

  defp check_typed(%{"type" => "date", "name" => name}, value) do
    with true <- is_binary(value),
         [day | _] <- String.split(value, "T"),
         {:ok, _} <- Date.from_iso8601(day) do
      :ok
    else
      _ -> {:error, "The #{name} field must be a valid date."}
    end
  end

  defp check_typed(%{"type" => "select", "name" => name} = field, value) do
    if value in List.wrap(field["options"]),
      do: :ok,
      else: {:error, "The selected #{name} is invalid."}
  end

  defp check_typed(_field, _value), do: :ok

  defp number?(value) when is_number(value), do: true

  defp number?(value) when is_binary(value),
    do: Regex.match?(~r/\A\s*[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\s*\z/, value)

  defp number?(_), do: false

  defp blank?(nil), do: true
  defp blank?([]), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  defp put_if(errors, true, key, message) do
    if Map.has_key?(errors, key), do: errors, else: Map.put(errors, key, [message])
  end

  defp put_if(errors, _, _key, _message), do: errors

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(_), do: nil

  defp object_json(%CustomObject{} = o) do
    %{
      id: o.id,
      name: o.name,
      slug: o.slug,
      description: o.description,
      fields_schema: o.fields_schema || [],
      created_at: o.inserted_at && DateTime.to_iso8601(o.inserted_at),
      updated_at: o.updated_at && DateTime.to_iso8601(o.updated_at)
    }
  end

  defp record_json(%CustomObjectRecord{} = r) do
    %{
      id: r.id,
      object_id: r.custom_object_id,
      data: r.data || %{},
      created_at: r.inserted_at && DateTime.to_iso8601(r.inserted_at),
      updated_at: r.updated_at && DateTime.to_iso8601(r.updated_at)
    }
  end

  defp find(id) do
    case parse_id(id) do
      nil -> nil
      int -> repo().get(CustomObject, int)
    end
  end

  # A record id that belongs to another object is not found.
  defp find_record(object, record_id) do
    case parse_id(record_id) do
      nil ->
        nil

      int ->
        repo().one(
          from(r in CustomObjectRecord,
            where: r.id == ^int and r.custom_object_id == ^object.id
          )
        )
    end
  end

  defp parse_id(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp not_found(conn),
    do: conn |> put_status(404) |> json(%{error: "Custom object not found"})

  defp records_path(conn, object) do
    fallback = "#{index_path()}/#{object.id}/records"

    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> rest = path} <- URI.parse(referer),
         false <- String.starts_with?(rest, "/") do
      path
    else
      _ -> fallback
    end
  end

  defp repo, do: Escalated.repo()

  defp index_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/custom-objects"
end
