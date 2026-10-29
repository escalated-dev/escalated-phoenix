defmodule Escalated.Services.GeneralSettings do
  @moduledoc """
  Typed, persistent settings supported by the general admin form.

  Database values override host configuration. Connection and compile-time
  configuration remain in the application environment. Writes validate the
  entire allowlist before a transaction, and upsert safely on every adapter.
  """
  import Ecto.Query

  alias Escalated.Schemas.EscalatedSetting
  alias Escalated.WidgetOrigins

  @defaults %{
    knowledge_base_enabled: false,
    knowledge_base_public: false,
    knowledge_base_feedback_enabled: false,
    show_powered_by: true,
    # Read while two-factor is switched on (Escalated.Services.TwoFactorService).
    two_factor_required: false
  }
  @boolean_keys @defaults |> Map.keys() |> Enum.map(&Atom.to_string/1)

  # Text settings. `widget_allowed_origins` is the admin half of the widget's
  # embedding allow list (Escalated.WidgetOrigins); the host's
  # `:widget_allowed_origins` config is the other half and is not shown here.
  @text_keys ["widget_allowed_origins"]
  @max_text_length 5000

  @keys Enum.sort(@boolean_keys ++ @text_keys)

  def supported_keys, do: @keys

  def all do
    stored =
      from(s in EscalatedSetting, where: s.key in ^@keys, select: {s.key, s.value})
      |> Escalated.repo().all()
      |> Map.new()

    booleans =
      Map.new(@defaults, fn {key, default} ->
        name = Atom.to_string(key)
        configured = boolean(configured(key, default), default)
        {name, boolean(Map.get(stored, name), configured)}
      end)

    Map.merge(booleans, Map.new(@text_keys, &{&1, Map.get(stored, &1) || ""}))
  end

  # `two_factor_required` defaults to `two_factor: [required: ...]` (env
  # ESCALATED_TWO_FACTOR_REQUIRED); the others to the key of the same name.
  defp configured(:two_factor_required, _default),
    do: Escalated.Services.TwoFactorService.configured_required?()

  defp configured(key, default), do: Application.get_env(:escalated, key, default)

  def enabled?(key) when is_atom(key), do: Map.fetch!(all(), Atom.to_string(key))

  def update(params) when is_map(params) do
    errors =
      Enum.reduce(params, %{}, fn {key, value}, errors ->
        cond do
          key not in @keys -> Map.put(errors, key, "This setting is not supported.")
          key in @text_keys -> text_error(errors, key, value)
          parse_boolean(value) == :error -> Map.put(errors, key, "Must be a boolean.")
          true -> errors
        end
      end)

    if map_size(errors) == 0, do: persist(params), else: {:error, errors}
  end

  def update(_), do: {:error, %{"settings" => "Must be an object."}}

  defp persist(params) do
    params
    |> Enum.sort()
    |> Enum.reduce(Ecto.Multi.new(), fn {key, value}, multi ->
      {value, type} = stored_value(key, value)

      changeset =
        EscalatedSetting.changeset(%EscalatedSetting{}, %{
          key: key,
          value: value,
          type: type,
          group: "general"
        })

      Ecto.Multi.insert(multi, key, changeset, upsert_options())
    end)
    |> Escalated.repo().transaction()
    |> case do
      {:ok, _rows} -> {:ok, all()}
      {:error, key, _reason, _changes} -> {:error, %{key => "Could not save this setting."}}
    end
  end

  defp stored_value(key, value) when key in @text_keys,
    do: {key |> normalize_text(value) |> elem(1), "string"}

  defp stored_value(_key, value) do
    {:ok, value} = parse_boolean(value)
    {if(value, do: "1", else: "0"), "boolean"}
  end

  defp text_error(errors, key, value) do
    case normalize_text(key, value) do
      {:ok, _} -> errors
      {:error, message} -> Map.put(errors, key, message)
    end
  end

  # One origin per line, normalised and without duplicates.
  defp normalize_text("widget_allowed_origins", value) when is_nil(value), do: {:ok, ""}

  defp normalize_text("widget_allowed_origins", value)
       when is_binary(value) and byte_size(value) <= @max_text_length do
    entries = WidgetOrigins.split(value)
    patterns = Enum.map(entries, &WidgetOrigins.normalize_pattern/1)

    if Enum.any?(patterns, &is_nil/1) do
      {:error,
       "Each site must be an origin such as https://shop.example.com or " <>
         "https://*.example.com, without a path."}
    else
      {:ok, patterns |> Enum.uniq() |> Enum.join("\n")}
    end
  end

  defp normalize_text("widget_allowed_origins", value) when is_binary(value),
    do: {:error, "Must be at most #{@max_text_length} characters."}

  defp normalize_text(_key, _value), do: {:error, "Must be text."}

  defp upsert_options do
    options = [on_conflict: {:replace, [:value, :type, :group, :updated_at]}]

    # MySQL selects the conflicting unique index itself. With a generated
    # primary key, the tenant/settings key is the only possible conflict here.
    # The legacy single-tenant namespace also uses the composite unique index.
    if Escalated.repo().__adapter__() == Ecto.Adapters.MyXQL,
      do: options,
      else: Keyword.put(options, :conflict_target, [:tenant_id, :key])
  end

  defp boolean(value, default) do
    case parse_boolean(value) do
      {:ok, parsed} -> parsed
      :error -> default
    end
  end

  defp parse_boolean(value) when value in [true, "true", 1, "1"], do: {:ok, true}
  defp parse_boolean(value) when value in [false, "false", 0, "0"], do: {:ok, false}
  defp parse_boolean(_), do: :error
end
