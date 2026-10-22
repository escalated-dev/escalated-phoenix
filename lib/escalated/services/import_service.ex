defmodule Escalated.Services.ImportService do
  @moduledoc """
  Runs an import, as escalated-laravel's `ImportService::run`: walk the
  adapter's entity types in order inside `Escalated.Import.Context.suppress/1`,
  resume each from its saved cursor and counters, write every record not yet in
  the source map, log failures, save progress after each batch, and stop
  between batches when the job has been paused or cancelled. A completed job
  drops its credentials.

  Contacts the host already has as users map to those users. Others become
  Escalated contacts (`Escalated.Schemas.Contact`) on guest tickets: Escalated
  cannot create host users.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Import.{Context, Credentials}
  alias Escalated.ImportAdapter.ExtractResult

  alias Escalated.Schemas.{
    Attachment,
    Contact,
    CustomField,
    Department,
    ImportJob,
    ImportSourceMap,
    Reply,
    SatisfactionRating,
    Tag,
    Ticket
  }

  @contact_prefix "contact:"

  @doc "Runs (or resumes) `job`. Returns the job as it ended."
  def run(%ImportJob{} = job) do
    case Escalated.ImportAdapter.find(job.platform) do
      nil ->
        update!(job, %{status: "failed"})
        raise "No adapter found for platform '#{job.platform}'."

      adapter ->
        job = update!(job, %{status: "importing", started_at: job.started_at || now()})
        credentials = Credentials.open(job.credentials) || %{}

        Context.suppress(fn -> import_entity_types(job, adapter, credentials) end)

        finish(reload(job))
    end
  end

  defp import_entity_types(job, adapter, credentials) do
    Enum.reduce_while(adapter.entity_types(), job, fn entity_type, job ->
      if stopped?(job),
        do: {:halt, job},
        else: next_entity_type(import_entity_type(job, adapter, entity_type, credentials))
    end)
  end

  defp next_entity_type({:cont, job}), do: {:cont, job}
  defp next_entity_type({:stopped, job}), do: {:halt, job}

  defp finish(%ImportJob{status: status} = job) when status in ["paused", "failed"], do: job

  defp finish(job),
    do: update!(job, %{status: "completed", completed_at: now(), credentials: nil})

  defp import_entity_type(job, adapter, entity_type, credentials) do
    saved = Map.get(job.progress || %{}, entity_type, %{})

    counters = %{
      processed: saved["processed"] || 0,
      skipped: saved["skipped"] || 0,
      failed: saved["failed"] || 0
    }

    batch(job, adapter, entity_type, credentials, saved["cursor"], counters)
  end

  defp batch(job, adapter, entity_type, credentials, cursor, counters) do
    %ExtractResult{} = result = adapter.extract(entity_type, credentials, cursor)

    {job, counters} =
      Enum.reduce(result.records, {job, counters}, fn record, {job, counters} ->
        import_record(job, entity_type, record, counters)
      end)

    progress =
      ImportJob.put_entity_progress(job.progress, entity_type,
        total: result.total_count,
        processed: counters.processed,
        skipped: counters.skipped,
        failed: counters.failed,
        cursor: result.cursor
      )

    job = update!(job, %{progress: progress})

    cond do
      stopped?(job) -> {:stopped, job}
      is_nil(result.cursor) -> {:cont, job}
      true -> batch(job, adapter, entity_type, credentials, result.cursor, counters)
    end
  end

  defp import_record(job, entity_type, record, counters) do
    record = stringify(record)
    source_id = if is_nil(record["source_id"]), do: "", else: to_string(record["source_id"])

    cond do
      source_id == "" ->
        {job, %{counters | failed: counters.failed + 1}}

      resolve(job, entity_type, source_id) != nil ->
        {job, %{counters | skipped: counters.skipped + 1}}

      true ->
        try do
          escalated_id = persist(job, entity_type, record)

          %ImportSourceMap{}
          |> ImportSourceMap.changeset(%{
            import_job_id: job.id,
            entity_type: entity_type,
            source_id: source_id,
            escalated_id: to_string(escalated_id)
          })
          |> repo().insert!()

          {job, %{counters | processed: counters.processed + 1}}
        rescue
          error ->
            log =
              ImportJob.append_error(
                job.error_log,
                entity_type,
                source_id,
                Exception.message(error)
              )

            {update!(job, %{error_log: log}), %{counters | failed: counters.failed + 1}}
        end
    end
  end

  # Paused, or cancelled (failed) from the Progress screen.
  defp stopped?(job) do
    status = repo().one(from(j in ImportJob, where: j.id == ^job.id, select: j.status))
    status in ["paused", "failed"]
  end

  defp resolve(job, entity_type, source_id) do
    repo().one(
      from(m in ImportSourceMap,
        where:
          m.import_job_id == ^job.id and m.entity_type == ^entity_type and
            m.source_id == ^source_id,
        select: m.escalated_id
      )
    )
  end

  defp ref(_job, _entity_type, nil), do: nil
  defp ref(_job, _entity_type, ""), do: nil
  defp ref(job, entity_type, source_id), do: resolve(job, entity_type, to_string(source_id))

  defp persist(_job, "agents", record) do
    host_user_id(record["email"]) ||
      raise "Agent with email '#{record["email"]}' not found in host application."
  end

  defp persist(_job, "contacts", record) do
    email = record["email"] || raise "Contact has no email."

    case host_user_id(email) do
      nil ->
        normalized = Contact.normalize_email(email)

        contact =
          repo().get_by(Contact, email: normalized) ||
            %Contact{}
            |> Contact.changeset(%{email: normalized, name: record["name"], metadata: %{}})
            |> repo().insert!()

        @contact_prefix <> to_string(contact.id)

      user_id ->
        user_id
    end
  end

  defp persist(_job, "tags", record) do
    name = to_string(record["name"] || "")

    tag =
      repo().one(from(t in Tag, where: t.name == ^name, limit: 1)) ||
        %Tag{} |> Tag.changeset(%{name: name}) |> repo().insert!()

    tag.id
  end

  defp persist(_job, "departments", record) do
    name = to_string(record["name"] || "")
    slug = slugify(name)

    department =
      repo().get_by(Department, slug: slug) ||
        %Department{}
        |> Department.changeset(%{name: name, slug: slug, is_active: true})
        |> repo().insert!()

    department.id
  end

  defp persist(_job, "custom_fields", record) do
    name = to_string(record["name"] || "")
    slug = slugify(name, "_")

    field =
      repo().get_by(CustomField, slug: slug) ||
        %CustomField{}
        |> CustomField.changeset(%{
          name: name,
          slug: slug,
          field_type: record["type"] || "text",
          entity_type: "ticket",
          options: if(is_list(record["options"]), do: record["options"], else: [])
        })
        |> repo().insert!()

    field.id
  end

  defp persist(job, "tickets", record) do
    subject = present(record["title"]) || present(record["subject"]) || "Imported ticket"
    status = record["status"]
    priority = record["priority"]

    %{
      subject: subject,
      description: present(record["description"]) || present(record["body"]) || subject,
      # As Laravel's TicketStatus::tryFrom / TicketPriority::tryFrom.
      status: if(status in Ticket.statuses(), do: status, else: "open"),
      priority: if(priority in Ticket.priorities(), do: priority, else: "medium"),
      metadata: if(is_map(record["metadata"]), do: record["metadata"], else: %{}),
      assigned_to: cast_user_id(ref(job, "agents", record["assignee_source_id"])),
      department_id: int(ref(job, "departments", record["department_source_id"]))
    }
    |> Map.merge(requester_attrs(ref(job, "contacts", record["requester_source_id"])))
    |> insert_ticket(job, record)
  end

  defp persist(job, "replies", record), do: persist_reply(job, record)
  defp persist(job, "attachments", record), do: persist_attachment(job, record)
  defp persist(job, "satisfaction_ratings", record), do: persist_rating(job, record)
  defp persist(_job, entity_type, _record), do: raise("Unknown entity type: #{entity_type}")

  defp requester_attrs(nil), do: %{}

  defp requester_attrs(@contact_prefix <> id) do
    case repo().get(Contact, int(id)) do
      nil -> %{}
      contact -> %{contact_id: contact.id, guest_email: contact.email, guest_name: contact.name}
    end
  end

  defp requester_attrs(user_id),
    do: %{requester_id: cast_user_id(user_id), requester_type: to_string(Escalated.user_schema())}

  defp insert_ticket(attrs, job, record) do
    tag_ids =
      record["tag_source_ids"]
      |> List.wrap()
      |> Enum.map(&ref(job, "tags", &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&int/1)

    ticket =
      %Ticket{}
      |> Ticket.changeset(attrs)
      |> Ecto.Changeset.put_assoc(:tags, repo().all(from(t in Tag, where: t.id in ^tag_ids)))
      |> repo().insert!()

    keep_timestamps(Ticket, ticket.id, record)
    ticket.id
  end

  defp persist_reply(job, record) do
    ticket_id =
      int(ref(job, "tickets", record["ticket_source_id"])) ||
        raise "Parent ticket not found for reply."

    author =
      ref(job, "agents", record["author_source_id"]) ||
        ref(job, "contacts", record["author_source_id"])

    author_id =
      case author do
        @contact_prefix <> _ -> nil
        other -> cast_user_id(other)
      end

    reply =
      %Reply{}
      |> Reply.changeset(%{
        ticket_id: ticket_id,
        body: to_string(record["body"] || ""),
        is_internal: record["is_internal_note"] == true,
        author_id: author_id
      })
      |> repo().insert!()

    keep_timestamps(Reply, reply.id, record)
    reply.id
  end

  defp persist_attachment(job, record) do
    {ticket_id, reply_id} =
      if record["parent_type"] == "ticket" do
        {int(ref(job, "tickets", record["parent_source_id"])) ||
           raise("Parent ticket not found for attachment."), nil}
      else
        reply_id =
          int(ref(job, "replies", record["parent_source_id"])) ||
            raise "Parent reply not found for attachment."

        {repo().get!(Reply, reply_id).ticket_id, reply_id}
      end

    attachment =
      %Attachment{}
      |> Attachment.changeset(%{
        original_filename: present(record["filename"]) || "unknown",
        mime_type: present(record["mime_type"]) || "application/octet-stream",
        size: record["size"] || 0,
        storage_key: to_string(record["path"] || ""),
        ticket_id: ticket_id,
        reply_id: reply_id
      })
      |> repo().insert!()

    attachment.id
  end

  defp persist_rating(job, record) do
    ticket_id =
      int(ref(job, "tickets", record["ticket_source_id"])) ||
        raise "Ticket not found for satisfaction rating."

    rating =
      %SatisfactionRating{}
      |> SatisfactionRating.changeset(%{
        ticket_id: ticket_id,
        rating: record["rating"] || record["score"],
        comment: record["comment"]
      })
      |> repo().insert!()

    rating.id
  end

  # The host user with this email, or nil.
  defp host_user_id(email) when is_binary(email) and email != "" do
    schema = Escalated.user_schema()

    if :email in schema.__schema__(:fields) do
      Escalated.user_repo().one(
        from(u in schema, where: u.email == ^email, select: u.id, limit: 1)
      )
    end
  end

  defp host_user_id(_), do: nil

  # Ticket and reply timestamps are set on insert; keep the source's.
  defp keep_timestamps(schema, id, record) do
    set =
      for key <- [:inserted_at, :updated_at],
          source = if(key == :inserted_at, do: record["created_at"], else: record["updated_at"]),
          is_binary(source),
          {:ok, at, _} <- [DateTime.from_iso8601(source)],
          do: {key, DateTime.truncate(at, :second)}

    if set != [], do: repo().update_all(from(r in schema, where: r.id == ^id), set: set)
  end

  defp update!(job, attrs), do: job |> ImportJob.changeset(attrs) |> repo().update!()

  defp reload(job), do: repo().get!(ImportJob, job.id)

  defp repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp stringify(record) when is_map(record),
    do: Map.new(record, fn {key, value} -> {to_string(key), value} end)

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_), do: nil

  defp int(nil), do: nil
  defp int(value) when is_integer(value), do: value
  defp int(value), do: String.to_integer(to_string(value))

  defp cast_user_id(nil), do: nil

  defp cast_user_id(value) do
    if Application.get_env(:escalated, :user_key_type, :integer) == :string,
      do: to_string(value),
      else: int(value)
  end

  defp slugify(name, separator \\ "-") do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, separator)
    |> String.trim(separator)
  end
end
