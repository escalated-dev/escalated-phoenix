defmodule Escalated.Schemas.ImportJob do
  @moduledoc """
  One import from an external platform, as escalated-laravel's `ImportJob`: its
  status, per-entity progress and cursors, error log and the source credentials
  (sealed by `Escalated.Import.Credentials`), which are dropped when the import
  completes or is cancelled.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  @transitions %{
    "pending" => ["authenticating"],
    "authenticating" => ["mapping", "failed"],
    "mapping" => ["importing", "failed"],
    "importing" => ["paused", "completed", "failed"],
    "paused" => ["importing", "failed"],
    "completed" => [],
    "failed" => ["mapping"]
  }

  @max_errors 10_000

  @primary_key {:id, :string, autogenerate: false}
  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}import_jobs" do
    field :tenant_id, :string, default: ""
    field :user_id, @user_id_type
    field :platform, :string
    field :status, :string, default: "pending"
    # Sealed source-platform credentials, read server-side by the import run
    # only. Never sent to a page (see `ImportController.job_json/1`), and
    # redacted from `inspect/1`.
    field :credentials, :string, redact: true
    field :field_mappings, :map, default: %{}
    field :progress, :map, default: %{}
    field :error_log, {:array, :map}, default: []
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def statuses, do: Map.keys(@transitions)

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :user_id,
      :platform,
      :status,
      :credentials,
      :field_mappings,
      :progress,
      :error_log,
      :started_at,
      :completed_at
    ])
    |> validate_required([:platform, :status])
    |> validate_inclusion(:status, statuses())
    |> then(fn changeset ->
      if get_field(changeset, :id),
        do: changeset,
        else: put_change(changeset, :id, Ecto.UUID.generate())
    end)
  end

  @doc "Whether the state machine allows `from` -> `to`."
  def transition?(from, to), do: to in Map.get(@transitions, from || "pending", [])

  def resumable?(%__MODULE__{status: status}), do: status in ["paused", "failed"]

  @doc """
  Merges counters for one entity type. A nil cursor keeps the last one, as
  Laravel's does: a resume re-reads one page, not the whole type.
  """
  def put_entity_progress(progress, entity_type, values) do
    current =
      Map.get(progress || %{}, entity_type) ||
        %{"total" => 0, "processed" => 0, "skipped" => 0, "failed" => 0, "cursor" => nil}

    current =
      Enum.reduce(values, current, fn
        {_key, nil}, acc -> acc
        {key, value}, acc -> Map.put(acc, to_string(key), value)
      end)

    Map.put(progress || %{}, entity_type, current)
  end

  @doc "Appends one error entry (capped, as Laravel's)."
  def append_error(log, entity_type, source_id, message) do
    log = log || []

    if length(log) < @max_errors do
      log ++
        [
          %{
            "entity_type" => entity_type,
            "source_id" => source_id,
            "error" => message,
            "timestamp" =>
              DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
          }
        ]
    else
      log
    end
  end
end
