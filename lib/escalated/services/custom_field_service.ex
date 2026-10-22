defmodule Escalated.Services.CustomFieldService do
  @moduledoc """
  Custom field definitions and the values tickets carry for them.

  Tickets send values as `custom_fields`, an object keyed by field slug (a
  numeric field id is accepted as a key too). Only active fields with the
  `ticket` context count; any other key is refused. Values are checked by
  `validate/2` before the ticket is written, and errors are keyed
  `custom_fields.<slug>`.

  Storage: `multi_select` is a JSON array string, `checkbox` is `"1"`/`"0"`,
  everything else the string as given. An empty value for an optional field
  deletes the stored one.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{CustomField, CustomFieldValue}

  @types ~w(text textarea select multi_select checkbox date number)
  @contexts ~w(ticket user organization)
  @entity "ticket"

  @doc "The field types an admin can create."
  def types, do: @types

  @doc "The contexts a field can belong to."
  def contexts, do: @contexts

  @doc "Every field, ordered by position, as the admin pages read it."
  def list_fields do
    from(f in CustomField, order_by: [asc: f.position, asc: f.id])
    |> repo().all()
  end

  @doc "Active ticket fields, ordered by position."
  def ticket_fields do
    from(f in CustomField,
      where: f.is_active == true and f.entity_type == @entity,
      order_by: [asc: f.position, asc: f.id]
    )
    |> repo().all()
  end

  @doc "A field serialised with every column, under escalated-laravel's names."
  def field_json(%CustomField{} = f) do
    %{
      id: f.id,
      name: f.name,
      slug: f.slug,
      type: f.field_type,
      context: f.entity_type,
      options: f.options,
      required: f.is_required,
      placeholder: f.placeholder,
      description: f.description,
      validation_rules: f.validation_rules,
      conditions: f.conditions,
      position: f.position,
      active: f.is_active,
      created_at: f.inserted_at && DateTime.to_iso8601(f.inserted_at),
      updated_at: f.updated_at && DateTime.to_iso8601(f.updated_at)
    }
  end

  @doc "The definition a ticket form reads."
  def definition_json(%CustomField{} = f) do
    %{
      id: f.id,
      name: f.name,
      slug: f.slug,
      type: f.field_type,
      options: f.options,
      required: f.is_required,
      placeholder: f.placeholder,
      description: f.description,
      position: f.position
    }
  end

  @doc "The active ticket definitions for a create page."
  def ticket_definitions, do: Enum.map(ticket_fields(), &definition_json/1)

  @doc "The active ticket definitions with the ticket's decoded `value` (nil when unset)."
  def ticket_values(ticket) do
    fields = ticket_fields()
    stored = stored_values(ticket.id, Enum.map(fields, & &1.id))

    Enum.map(fields, fn f ->
      Map.put(definition_json(f), :value, decode(f, Map.get(stored, f.id)))
    end)
  end

  defp stored_values(_ticket_id, []), do: %{}

  defp stored_values(ticket_id, field_ids) do
    from(v in CustomFieldValue,
      where:
        v.entity_type == @entity and v.entity_id == ^ticket_id and
          v.custom_field_id in ^field_ids,
      select: {v.custom_field_id, v.value}
    )
    |> repo().all()
    |> Map.new()
  end

  @doc """
  The `custom_fields` object a ticket write sent: the `custom_fields` key, or
  the older camelCase `customFields`. `:absent` when neither was sent.
  """
  def param(params) when is_map(params) do
    cond do
      Map.has_key?(params, "custom_fields") -> params["custom_fields"]
      Map.has_key?(params, "customFields") -> params["customFields"]
      Map.has_key?(params, :custom_fields) -> params[:custom_fields]
      true -> :absent
    end
  end

  def param(_), do: :absent

  @doc """
  Checks the values a ticket write sent.

  `mode` is `:create` (every required field must be present and non-empty) or
  `:update` (only the keys sent are checked; `:absent` changes nothing).
  Returns `{:ok, changes}`, a list of `{field, encoded_value_or_nil}`, or
  `{:error, %{"custom_fields.<slug>" => [message]}}`.
  """
  def validate(sent, mode) when mode in [:create, :update] do
    fields = ticket_fields()

    cond do
      sent == :absent and mode == :update ->
        {:ok, []}

      sent in [:absent, nil] ->
        check(fields, %{}, mode)

      is_map(sent) ->
        check(fields, sent, mode)

      true ->
        {:error, %{"custom_fields" => ["must be an object keyed by field slug"]}}
    end
  end

  defp check(fields, sent, mode) do
    by_key =
      Enum.flat_map(fields, fn f -> [{f.slug, f}, {to_string(f.id), f}] end) |> Map.new()

    {changes, errors} =
      Enum.reduce(sent, {[], %{}}, fn {key, value}, {changes, errors} ->
        key = to_string(key)

        case Map.fetch(by_key, key) do
          :error ->
            {changes, Map.put(errors, "custom_fields.#{key}", ["is not a ticket field"])}

          {:ok, field} ->
            case check_value(field, value) do
              {:ok, encoded} ->
                {[{field, encoded} | changes], errors}

              {:error, message} ->
                {changes, Map.put(errors, "custom_fields.#{field.slug}", [message])}
            end
        end
      end)

    errors =
      if mode == :create do
        sent_ids = MapSet.new(changes, fn {f, value} -> if value != nil, do: f.id end)

        Enum.reduce(fields, errors, fn f, acc ->
          key = "custom_fields.#{f.slug}"

          if f.is_required and not MapSet.member?(sent_ids, f.id) and
               not Map.has_key?(acc, key),
             do: Map.put(acc, key, [required_message(f)]),
             else: acc
        end)
      else
        errors
      end

    if errors == %{}, do: {:ok, Enum.reverse(changes)}, else: {:error, errors}
  end

  defp check_value(field, value) do
    cond do
      blank?(value) and field.is_required -> {:error, required_message(field)}
      blank?(value) -> {:ok, nil}
      true -> encode(field.field_type, field, value)
    end
  end

  defp required_message(field), do: "The #{field.name} field is required."

  defp blank?(nil), do: true
  defp blank?([]), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  defp encode("number", field, value) when is_number(value),
    do: encode("number", field, to_string(value))

  defp encode("number", field, value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(~r/\A[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?\z/, trimmed),
      do: {:ok, trimmed},
      else: {:error, "The #{field.name} field must be a number."}
  end

  defp encode("date", field, value) when is_binary(value) do
    with true <- Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, value),
         {:ok, _} <- Date.from_iso8601(value) do
      {:ok, value}
    else
      _ -> {:error, "The #{field.name} field must be a valid date (YYYY-MM-DD)."}
    end
  end

  defp encode("checkbox", _field, value) when value in [true, 1, "1", "true"], do: {:ok, "1"}
  defp encode("checkbox", _field, value) when value in [false, 0, "0", "false"], do: {:ok, "0"}

  defp encode("checkbox", field, _value),
    do: {:error, "The #{field.name} field must be true or false."}

  defp encode("select", field, value) when is_binary(value) do
    if value in (field.options || []),
      do: {:ok, value},
      else: {:error, "The selected #{field.name} is invalid."}
  end

  defp encode("multi_select", field, values) when is_list(values) do
    if Enum.all?(values, &(is_binary(&1) and &1 in (field.options || []))),
      do: {:ok, Jason.encode!(values)},
      else: {:error, "The selected #{field.name} is invalid."}
  end

  defp encode("multi_select", field, _value),
    do: {:error, "The #{field.name} field must be a list."}

  defp encode("textarea", _field, value) when is_binary(value), do: {:ok, value}

  defp encode(type, field, value) when type in ["text", "url"] and is_binary(value) do
    if String.length(value) <= 255,
      do: {:ok, value},
      else: {:error, "The #{field.name} field may not be greater than 255 characters."}
  end

  defp encode(_type, field, _value),
    do: {:error, "The #{field.name} field has an invalid value."}

  @doc "Writes checked `changes` for a ticket: nil deletes, anything else is stored."
  def save(ticket_id, changes) do
    Enum.each(changes, fn {field, value} ->
      existing =
        repo().one(
          from(v in CustomFieldValue,
            where:
              v.custom_field_id == ^field.id and v.entity_type == @entity and
                v.entity_id == ^ticket_id
          )
        )

      case {existing, value} do
        {nil, nil} ->
          :ok

        {%CustomFieldValue{} = row, nil} ->
          repo().delete!(row)

        {nil, value} ->
          %CustomFieldValue{}
          |> CustomFieldValue.changeset(%{
            custom_field_id: field.id,
            entity_type: @entity,
            entity_id: ticket_id,
            value: value
          })
          |> repo().insert!()

        {row, value} ->
          row |> CustomFieldValue.changeset(%{value: value}) |> repo().update!()
      end
    end)
  end

  @doc "A stored value decoded for its field type."
  def decode(_field, nil), do: nil
  def decode(%CustomField{field_type: "checkbox"}, value), do: value in ["1", "true"]

  def decode(%CustomField{field_type: "multi_select"}, value) do
    case Jason.decode(value) do
      {:ok, list} when is_list(list) -> list
      _ -> [value]
    end
  end

  def decode(%CustomField{field_type: "number"}, value) do
    case Integer.parse(value) do
      {int, ""} ->
        int

      _ ->
        case Float.parse(value) do
          {float, ""} -> float
          _ -> value
        end
    end
  end

  def decode(_field, value), do: value

  @doc """
  The slug for a new field named `name`: `CustomField.slugify/1`, with `_2`,
  `_3`, ... appended while it is taken.
  """
  def unique_slug(name) do
    base = CustomField.slugify(name)
    base = if base == "", do: "field", else: base

    taken =
      from(f in CustomField,
        # `_` in the pattern matches any character; the exact checks below
        # only count the real `<base>` and `<base>_<n>` slugs.
        where: like(f.slug, ^(base <> "%")),
        select: f.slug
      )
      |> repo().all()
      |> MapSet.new()

    if MapSet.member?(taken, base) do
      Stream.iterate(2, &(&1 + 1))
      |> Enum.find_value(fn n ->
        candidate = "#{base}_#{n}"
        if MapSet.member?(taken, candidate), do: nil, else: candidate
      end)
    else
      base
    end
  end

  defp repo, do: Escalated.repo()
end
