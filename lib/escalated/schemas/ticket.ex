defmodule Escalated.Schemas.Ticket do
  @moduledoc """
  Ecto schema for support tickets.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @statuses ~w(open in_progress waiting_on_customer waiting_on_agent escalated resolved closed reopened snoozed live)
  @priorities ~w(low medium high urgent critical)
  @ticket_types ~w(question problem incident task)
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}tickets" do
    field :reference, :string
    field :subject, :string
    field :description, :string
    field :status, :string, default: "open"
    field :priority, :string, default: "medium"
    field :ticket_type, :string
    field :assigned_to, @user_id_type
    field :requester_id, @user_id_type
    field :requester_type, :string
    field :guest_name, :string
    field :guest_email, :string
    field :guest_token, :string
    # First-class Contact FK (Pattern B convergence).
    field :contact_id, :integer
    field :metadata, :map, default: %{}

    # Chat fields
    field :channel, :string
    field :chat_ended_at, :utc_datetime
    field :chat_metadata, :map, default: %{}

    # Snooze fields
    field :snoozed_until, :utc_datetime
    field :snoozed_by, @user_id_type
    field :status_before_snooze, :string

    # SLA fields
    field :sla_breached, :boolean, default: false
    field :sla_first_response_due_at, :utc_datetime
    field :sla_resolution_due_at, :utc_datetime
    field :first_response_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :closed_at, :utc_datetime

    belongs_to :department, Escalated.Schemas.Department
    belongs_to :sla_policy, Escalated.Schemas.SlaPolicy

    has_many :replies, Escalated.Schemas.Reply
    has_many :activities, Escalated.Schemas.TicketActivity
    has_many :attachments, Escalated.Schemas.Attachment
    has_many :ticket_subjects, Escalated.Schemas.TicketSubject

    many_to_many :tags, Escalated.Schemas.Tag,
      join_through:
        "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}ticket_tags",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def priorities, do: @priorities
  def ticket_types, do: @ticket_types

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :subject,
      :description,
      :status,
      :priority,
      :ticket_type,
      :assigned_to,
      :requester_id,
      :requester_type,
      :guest_name,
      :guest_email,
      :guest_token,
      :contact_id,
      :department_id,
      :sla_policy_id,
      :metadata,
      :snoozed_until,
      :snoozed_by,
      :status_before_snooze,
      :sla_breached,
      :sla_first_response_due_at,
      :sla_resolution_due_at,
      :first_response_at,
      :resolved_at,
      :closed_at,
      :channel,
      :chat_ended_at,
      :chat_metadata
    ])
    |> validate_required([:subject, :description])
    |> validate_length(:subject, max: 255)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> validate_inclusion(:ticket_type, @ticket_types ++ [nil])
    |> unique_constraint(:reference)
    |> maybe_set_reference()
  end

  # Crockford's base32: the digits and the uppercase letters without I, L, O and
  # U, so a reference read aloud or copied by hand has no 1/I/L or 0/O to mix
  # up. Every character is in the inbound subject-tag pattern `[0-9A-Z-]`.
  @reference_alphabet "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @doc """
  Generates a ticket reference: `ESC-`, the year and month (`YYMM`), and 8
  characters of Crockford base32 carrying 40 random bits, e.g.
  `ESC-2609-7KQ2M9XH`.

  The reference is random, so it can match one already stored.
  `Escalated.Services.TicketService.insert/1` retries under a fresh reference
  when it does. Older references, with six hex characters, are stored as they
  are and keep resolving.
  """
  def generate_reference do
    generate_reference(DateTime.utc_now(), :crypto.strong_rand_bytes(5))
  end

  @doc false
  # The deterministic half of generate_reference/0: each 5-bit group of the
  # 40 random bits becomes one character.
  def generate_reference(%DateTime{} = now, <<_::40>> = random) do
    suffix = for <<index::5 <- random>>, into: "", do: binary_part(@reference_alphabet, index, 1)
    "ESC-" <> Calendar.strftime(now, "%y%m") <> "-" <> suffix
  end

  @doc """
  True when an insert failed because the ticket's reference is already taken.
  """
  def reference_taken?(%Ecto.Changeset{errors: errors}) do
    case Keyword.get(errors, :reference) do
      {_message, opts} -> opts[:constraint] == :unique
      nil -> false
    end
  end

  @doc false
  # Replaces the reference on a ticket changeset whose insert collided.
  def put_new_reference(changeset), do: put_change(changeset, :reference, new_reference())

  # Scopes as composable query functions

  def by_open(query \\ __MODULE__) do
    open_statuses = ~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened)
    from(t in query, where: t.status in ^open_statuses)
  end

  def unassigned(query \\ __MODULE__) do
    from(t in query, where: is_nil(t.assigned_to))
  end

  def assigned_to(query \\ __MODULE__, agent_id) do
    from(t in query, where: t.assigned_to == ^agent_id)
  end

  def by_department(query \\ __MODULE__, department_id) do
    from(t in query, where: t.department_id == ^department_id)
  end

  def by_priority(query \\ __MODULE__, priority) do
    from(t in query, where: t.priority == ^priority)
  end

  def breached_sla(query \\ __MODULE__) do
    now = DateTime.utc_now()

    from(t in query,
      where:
        t.sla_breached == true or
          (t.sla_first_response_due_at < ^now and is_nil(t.first_response_at)) or
          (t.sla_resolution_due_at < ^now and is_nil(t.resolved_at) and
             t.status not in ["resolved", "closed"])
    )
  end

  def search(query \\ __MODULE__, term) do
    pattern = "%#{term}%"

    from(t in query,
      where:
        ilike(t.subject, ^pattern) or
          ilike(t.description, ^pattern) or
          ilike(t.reference, ^pattern)
    )
  end

  def recent(query \\ __MODULE__) do
    from(t in query, order_by: [desc: t.inserted_at])
  end

  def snoozed(query \\ __MODULE__) do
    from(t in query, where: t.status == "snoozed" and not is_nil(t.snoozed_until))
  end

  def wake_due(query \\ __MODULE__) do
    now = DateTime.utc_now()
    from(t in query, where: t.status == "snoozed" and t.snoozed_until <= ^now)
  end

  def open?(ticket) do
    ticket.status in ~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened)
  end

  def snoozed?(ticket) do
    ticket.status == "snoozed" && ticket.snoozed_until != nil
  end

  def live_chat?(ticket) do
    ticket.channel == "chat"
  end

  def chat_active?(ticket) do
    live_chat?(ticket) && ticket.status == "live" && is_nil(ticket.chat_ended_at)
  end

  def by_channel(query \\ __MODULE__, channel) do
    from(t in query, where: t.channel == ^channel)
  end

  def live_chats(query \\ __MODULE__) do
    from(t in query, where: t.channel == "chat" and t.status == "live")
  end

  # Private

  defp maybe_set_reference(changeset) do
    case get_field(changeset, :reference) do
      nil -> put_change(changeset, :reference, new_reference())
      _ -> changeset
    end
  end

  # :ticket_reference_generator exists so a test can force a collision; it is
  # not a host setting.
  defp new_reference do
    Escalated.config(:ticket_reference_generator, &generate_reference/0).()
  end
end
