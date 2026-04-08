defmodule Escalated.Schemas.ChatSession do
  @moduledoc """
  Ecto schema for live chat sessions.

  A chat session is linked to a ticket with channel "chat".
  It tracks the lifecycle from visitor waiting, through active
  conversation with an agent, to ended or abandoned.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @statuses ~w(waiting active ended abandoned)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}chat_sessions" do
    field :status, :string, default: "waiting"
    field :agent_id, :integer
    field :visitor_user_agent, :string
    field :visitor_ip, :string
    field :visitor_page_url, :string
    field :agent_joined_at, :utc_datetime
    field :last_activity_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :ticket, Escalated.Schemas.Ticket

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :status, :agent_id, :ticket_id,
      :visitor_user_agent, :visitor_ip, :visitor_page_url,
      :agent_joined_at, :last_activity_at, :ended_at
    ])
    |> validate_required([:ticket_id])
    |> validate_inclusion(:status, @statuses)
  end

  def active(query \\ __MODULE__) do
    from(s in query, where: s.status in ["waiting", "active"])
  end

  def waiting(query \\ __MODULE__) do
    from(s in query, where: s.status == "waiting")
  end

  def by_agent(query \\ __MODULE__, agent_id) do
    from(s in query, where: s.agent_id == ^agent_id)
  end

  def idle_before(query \\ __MODULE__, threshold) do
    from(s in query,
      where: s.status in ["waiting", "active"] and s.last_activity_at < ^threshold
    )
  end

  def waiting_before(query \\ __MODULE__, threshold) do
    from(s in query,
      where: s.status == "waiting" and s.inserted_at < ^threshold
    )
  end

  def active?(session), do: session.status == "active"
  def waiting?(session), do: session.status == "waiting"
end
