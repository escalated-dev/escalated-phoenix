defmodule Escalated.Test.FakeImportAdapter do
  @moduledoc """
  An import source for tests. It stands in for a plugin-provided adapter
  (Zendesk, Freshdesk, ...): core never talks to a third-party API itself, it
  only drives the adapters on the `"import.adapters"` filter.

  The records are fixed: two contacts (one already a host user in the tests),
  one tag, three tickets served two to a page, and two replies.

  The import runs in a task, so a test steers it through application env:
  `:fake_import_listener` (a pid told `{:extract, type, cursor, importing?}`
  on every batch) and `:fake_import_on_extract` (a fun run before each batch).
  """
  @behaviour Escalated.ImportAdapter

  alias Escalated.ImportAdapter.ExtractResult

  @token "secret-token"
  @page_size 2

  @records %{
    "contacts" => [
      %{"source_id" => "c1", "email" => "ada@customer.test", "name" => "Ada Customer"},
      %{"source_id" => "c2", "email" => "bob@customer.test", "name" => "Bob Customer"}
    ],
    "tags" => [%{"source_id" => "t1", "name" => "Billing"}],
    "tickets" => [
      %{
        "source_id" => "k1",
        "title" => "Refund please",
        "description" => "Charged twice.",
        "status" => "open",
        "priority" => "high",
        "requester_source_id" => "c1",
        "tag_source_ids" => ["t1"],
        "created_at" => "2024-01-02T03:04:05Z"
      },
      %{
        "source_id" => "k2",
        "title" => "Login broken",
        "status" => "resolved",
        "priority" => "urgent",
        "requester_source_id" => "c2"
      },
      %{
        "source_id" => "k3",
        "title" => "Feature idea",
        "status" => "not-a-status",
        "requester_source_id" => "c1"
      }
    ],
    "replies" => [
      %{
        "source_id" => "r1",
        "ticket_source_id" => "k1",
        "body" => "Looking into it",
        "author_source_id" => "c1"
      },
      %{
        "source_id" => "r2",
        "ticket_source_id" => "k2",
        "body" => "Internal note",
        "is_internal_note" => true
      }
    ]
  }

  def token, do: @token
  def credentials, do: %{"subdomain" => "acme", "api_token" => @token}

  def credential_fields_json,
    do: [
      %{"name" => "subdomain", "label" => "Subdomain", "type" => "text", "help" => "acme"},
      %{"name" => "api_token", "label" => "API token", "type" => "password", "help" => ""}
    ]

  def ticket_source_fields,
    do: [
      %{
        "name" => "subject",
        "label" => "Subject",
        "escalated_options" => ["title", "description"]
      },
      %{"name" => "state", "label" => "State", "escalated_options" => ["status"]}
    ]

  @impl true
  def name, do: "fakedesk"

  @impl true
  def display_name, do: "FakeDesk"

  @impl true
  def credential_fields, do: credential_fields_json()

  @impl true
  def test_connection(%{"subdomain" => "down"}), do: raise("FakeDesk is unreachable")
  def test_connection(credentials), do: credentials["api_token"] == @token

  @impl true
  def entity_types, do: ~w(contacts tags tickets replies)

  @impl true
  def default_field_mappings("tickets"), do: %{"subject" => "title", "state" => "status"}
  def default_field_mappings(_), do: %{}

  @impl true
  def available_source_fields(entity_type, credentials) do
    if pid = Application.get_env(:escalated, :fake_import_listener),
      do: send(pid, {:source_fields, credentials})

    if entity_type == "tickets", do: ticket_source_fields(), else: []
  end

  @impl true
  def extract(entity_type, credentials, cursor) do
    if credentials["api_token"] != @token, do: raise("bad credentials")

    if pid = Application.get_env(:escalated, :fake_import_listener),
      do: send(pid, {:extract, entity_type, cursor, Escalated.Import.Context.importing?()})

    case Application.get_env(:escalated, :fake_import_on_extract) do
      fun when is_function(fun, 2) -> fun.(entity_type, cursor)
      _ -> :ok
    end

    records = Map.fetch!(@records, entity_type)
    offset = String.to_integer(cursor || "0")
    next = offset + @page_size

    %ExtractResult{
      records: Enum.slice(records, offset, @page_size),
      cursor: if(next < length(records), do: Integer.to_string(next)),
      total_count: length(records)
    }
  end
end
