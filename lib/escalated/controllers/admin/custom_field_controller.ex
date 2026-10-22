defmodule Escalated.Controllers.Admin.CustomFieldController do
  @moduledoc """
  Admin CRUD over custom field definitions, serving
  `Escalated/Admin/CustomFields/Index` and `Escalated/Admin/CustomFields/Form`
  with the props escalated-laravel's `Admin\\CustomFieldController` sends.

  Tickets carry values for the active `ticket` fields; see
  `Escalated.Services.CustomFieldService`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.CustomField
  alias Escalated.Services.CustomFieldService

  def index(conn, _params) do
    fields = Enum.map(CustomFieldService.list_fields(), &CustomFieldService.field_json/1)
    UIRenderer.render_page(conn, "Escalated/Admin/CustomFields/Index", %{fields: fields})
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/CustomFields/Form", %{
      contexts: CustomFieldService.contexts()
    })
  end

  def edit(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      field ->
        UIRenderer.render_page(conn, "Escalated/Admin/CustomFields/Form", %{
          field: CustomFieldService.field_json(field),
          contexts: CustomFieldService.contexts()
        })
    end
  end

  def create(conn, params) do
    case form_attrs(params) do
      {:ok, attrs} ->
        attrs = Map.put(attrs, :slug, CustomFieldService.unique_slug(attrs.name))

        case %CustomField{} |> CustomField.changeset(attrs) |> repo().insert() do
          {:ok, _} ->
            conn |> put_flash(:info, "Custom field created.") |> redirect(to: index_path())

          {:error, changeset} ->
            FormResponse.invalid(conn, changeset, index_path() <> "/create")
        end

      {:error, errors} ->
        FormResponse.invalid(conn, errors, index_path() <> "/create")
    end
  end

  def update(conn, %{"id" => id} = params) do
    with field when not is_nil(field) <- find(id),
         {:ok, attrs} <- form_attrs(params),
         {:ok, _} <- field |> CustomField.changeset(attrs) |> repo().update() do
      conn |> put_flash(:info, "Custom field updated.") |> redirect(to: index_path())
    else
      nil -> not_found(conn)
      {:error, errors} -> FormResponse.invalid(conn, errors, "#{index_path()}/#{id}/edit")
    end
  end

  def delete(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      field ->
        # The values go with it (ON DELETE CASCADE, and explicitly for
        # databases that do not enforce foreign keys).
        repo().transaction(fn ->
          from(v in Escalated.Schemas.CustomFieldValue, where: v.custom_field_id == ^field.id)
          |> repo().delete_all()

          repo().delete!(field)
        end)

        conn |> put_flash(:info, "Custom field deleted.") |> redirect(to: index_path())
    end
  end

  @doc "Sets positions from `positions: [{id, position}]` and redirects back."
  def reorder(conn, params) do
    case reorder_items(params["positions"]) do
      {:ok, items} ->
        repo().transaction(fn ->
          Enum.each(items, fn {id, position} ->
            from(f in CustomField, where: f.id == ^id)
            |> repo().update_all(set: [position: position])
          end)
        end)

        conn |> put_flash(:info, "Fields reordered.") |> redirect(to: back_path(conn))

      {:error, errors} ->
        FormResponse.invalid(conn, errors, index_path())
    end
  end

  # Private

  # Laravel's rules: name required (max 255), type and context from their
  # lists, options an array (at least one for select types), placeholder max
  # 255, booleans and an integer position.
  defp form_attrs(params) do
    name = trimmed(params["name"])
    type = params["type"]
    context = params["context"]
    options = params["options"]

    errors =
      []
      |> add_if(name in [nil, ""], "name", "The name field is required.")
      |> add_if(
        is_binary(name) and String.length(name) > 255,
        "name",
        "The name may not be greater than 255 characters."
      )
      |> add_if(type not in CustomFieldService.types(), "type", "The selected type is invalid.")
      |> add_if(
        context not in CustomFieldService.contexts(),
        "context",
        "The selected context is invalid."
      )
      |> add_if(
        not (is_nil(options) or (is_list(options) and Enum.all?(options, &is_binary/1))),
        "options",
        "The options must be a list of strings."
      )
      |> add_if(
        type in ["select", "multi_select"] and options_list(options) == [],
        "options",
        "A select field needs at least one option."
      )
      |> add_if(
        is_binary(params["placeholder"]) and String.length(params["placeholder"]) > 255,
        "placeholder",
        "The placeholder may not be greater than 255 characters."
      )
      |> add_if(
        not (is_nil(params["position"]) or integer(params["position"]) != :error),
        "position",
        "The position must be an integer."
      )
      |> add_if(
        not (is_nil(params["validation_rules"]) or is_list(params["validation_rules"]) or
               is_map(params["validation_rules"])),
        "validation_rules",
        "The validation rules must be an array."
      )
      |> Map.new(fn {k, v} -> {k, [v]} end)

    if errors == %{} do
      {:ok,
       %{
         name: name,
         field_type: type,
         entity_type: context,
         options: options_list(options),
         is_required: truthy?(params["required"]),
         is_active: if(Map.has_key?(params, "active"), do: truthy?(params["active"]), else: true),
         placeholder: blank_to_nil(params["placeholder"]),
         description: blank_to_nil(params["description"]),
         validation_rules: params["validation_rules"],
         position: integer(params["position"]) |> then(&if(&1 == :error, do: 0, else: &1))
       }}
    else
      {:error, errors}
    end
  end

  defp reorder_items(items) when is_list(items) and items != [] do
    parsed =
      Enum.map(items, fn
        %{} = item -> {integer(item["id"]), integer(item["position"])}
        _ -> {:error, :error}
      end)

    ids = for {id, _} <- parsed, id != :error, do: id
    known = from(f in CustomField, where: f.id in ^ids, select: f.id) |> repo().all()

    errors =
      parsed
      |> Enum.with_index()
      |> Enum.flat_map(fn {{id, position}, i} ->
        id_error =
          if id == :error or id not in known,
            do: [{"positions.#{i}.id", ["The selected id is invalid."]}],
            else: []

        position_error =
          if position == :error,
            do: [{"positions.#{i}.position", ["The position must be an integer."]}],
            else: []

        id_error ++ position_error
      end)
      |> Map.new()

    if errors == %{}, do: {:ok, parsed}, else: {:error, errors}
  end

  defp reorder_items(_), do: {:error, %{"positions" => ["The positions field is required."]}}

  defp add_if(errors, true, key, message) do
    if List.keymember?(errors, key, 0), do: errors, else: errors ++ [{key, message}]
  end

  defp add_if(errors, _, _key, _message), do: errors

  defp options_list(options) when is_list(options),
    do: options |> Enum.filter(&is_binary/1) |> Enum.reject(&(String.trim(&1) == ""))

  defp options_list(_), do: []

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp integer(_), do: :error

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(_), do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp blank_to_nil(_), do: nil

  defp truthy?(value), do: value in [true, "true", "1", 1, "on"]

  defp find(id) do
    case integer(to_string(id)) do
      :error -> nil
      int -> repo().get(CustomField, int)
    end
  end

  defp back_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> rest = path} <- URI.parse(referer),
         false <- String.starts_with?(rest, "/") do
      path
    else
      _ -> index_path()
    end
  end

  defp not_found(conn),
    do: conn |> put_status(404) |> json(%{error: "Custom field not found"})

  defp repo, do: Escalated.repo()

  defp index_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/custom-fields"
end
