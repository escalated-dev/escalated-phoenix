defmodule Escalated.ImportAdapter do
  @moduledoc """
  A source the admin Import wizard can import from, as escalated-laravel's
  `Contracts\\ImportAdapter`.

  Core ships none. A host or a plugin provides adapters (a Zendesk or Freshdesk
  one, say) through the `"import.adapters"` filter, which threads a list of
  modules implementing this behaviour:

      config :escalated,
        filters: %{"import.adapters" => [fn adapters -> adapters ++ [MyApp.ZendeskImport] end]}

  or from an active plugin's `handle_filter("import.adapters", adapters, _)`.

  `extract/3` returns records already normalized (`"source_id"`, `"title"`,
  `"requester_source_id"`, `"tag_source_ids"`, `"ticket_source_id"`, ...);
  see `Escalated.Services.ImportService`.
  """

  defmodule ExtractResult do
    @moduledoc "One batch from `c:Escalated.ImportAdapter.extract/3`. A nil `cursor` means exhausted."
    defstruct records: [], cursor: nil, total_count: nil

    @type t :: %__MODULE__{
            records: [map()],
            cursor: String.t() | nil,
            total_count: non_neg_integer() | nil
          }
  end

  @typedoc ~s[A map with "name", "label", "type" (text, password or url) and "help".]
  @type credential_field :: map()

  @doc "Unique slug, e.g. `\"zendesk\"`."
  @callback name() :: String.t()

  @doc "Human-readable name, e.g. `\"Zendesk\"`."
  @callback display_name() :: String.t()

  @callback credential_fields() :: [credential_field()]

  @doc "Validate credentials with a test call. May raise: the message is shown."
  @callback test_connection(credentials :: map()) :: boolean()

  @doc "Importable entity types in dependency order."
  @callback entity_types() :: [String.t()]

  @doc "Default mappings for an entity type: source field => Escalated field."
  @callback default_field_mappings(entity_type :: String.t()) :: map()

  @doc "Source fields as the Mapping screen lists them: `name`, `label`, `escalated_options`."
  @callback available_source_fields(entity_type :: String.t(), credentials :: map()) :: [map()]

  @doc "One batch of records."
  @callback extract(entity_type :: String.t(), credentials :: map(), cursor :: String.t() | nil) ::
              ExtractResult.t()

  @doc "The registered adapters."
  @spec all() :: [module()]
  def all do
    "import.adapters"
    |> Escalated.Plugins.Hooks.apply_filters([])
    |> List.wrap()
    |> Enum.filter(
      &(is_atom(&1) and Code.ensure_loaded?(&1) and function_exported?(&1, :name, 0))
    )
  end

  @doc "The adapter whose `name/0` is `platform`, or nil."
  @spec find(String.t()) :: module() | nil
  def find(platform), do: Enum.find(all(), &(&1.name() == platform))
end
