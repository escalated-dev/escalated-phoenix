defmodule Escalated.Services.GeneralSettings do
  @moduledoc """
  Typed, persistent settings supported by the general admin form.

  Database values override host configuration. Connection and compile-time
  configuration remain in the application environment. Writes validate the
  entire allowlist before a transaction, and upsert safely on every adapter.
  """
  import Ecto.Query

  alias Escalated.Schemas.EscalatedSetting

  @defaults %{
    knowledge_base_enabled: false,
    knowledge_base_public: false,
    knowledge_base_feedback_enabled: false,
    show_powered_by: true
  }
  @keys @defaults |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort()

  def supported_keys, do: @keys

  def all do
    stored =
      from(s in EscalatedSetting, where: s.key in ^@keys, select: {s.key, s.value})
      |> Escalated.repo().all()
      |> Map.new()

    Map.new(@defaults, fn {key, default} ->
      name = Atom.to_string(key)
      configured = boolean(Application.get_env(:escalated, key, default), default)
      {name, boolean(Map.get(stored, name), configured)}
    end)
  end

  def enabled?(key) when is_atom(key), do: Map.fetch!(all(), Atom.to_string(key))

  def update(params) when is_map(params) do
    errors =
      Enum.reduce(params, %{}, fn {key, value}, errors ->
        cond do
          key not in @keys -> Map.put(errors, key, "This setting is not supported.")
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
      {:ok, value} = parse_boolean(value)

      changeset =
        EscalatedSetting.changeset(%EscalatedSetting{}, %{
          key: key,
          value: if(value, do: "1", else: "0"),
          type: "boolean",
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

  defp upsert_options do
    options = [on_conflict: {:replace, [:value, :type, :group, :updated_at]}]

    # MySQL selects the conflicting unique index itself. With a generated
    # primary key, the settings key is the only possible conflict here.
    if Escalated.repo().__adapter__() == Ecto.Adapters.MyXQL,
      do: options,
      else: Keyword.put(options, :conflict_target, [:key])
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
