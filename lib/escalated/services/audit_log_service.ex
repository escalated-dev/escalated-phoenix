defmodule Escalated.Services.AuditLogService do
  @moduledoc "Service for recording and querying audit log entries."

  import Ecto.Query
  alias Escalated.Schemas.AuditLog

  @doc "Record an audit log entry."
  def log(repo, attrs) when is_map(attrs) do
    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> repo.insert()
  end

  @doc "Get logs for a specific entity."
  def logs_for_entity(repo, entity_type, entity_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLog
    |> AuditLog.for_entity(entity_type, entity_id)
    |> limit(^limit)
    |> repo.all()
  end

  @doc "Get logs by a specific performer."
  def logs_by_performer(repo, performer_type, performer_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    AuditLog
    |> AuditLog.by_performer(performer_type, performer_id)
    |> limit(^limit)
    |> repo.all()
  end
end
