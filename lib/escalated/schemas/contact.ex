defmodule Escalated.Schemas.Contact do
  @moduledoc """
  First-class identity for guest requesters (Pattern B).

  Deduped by email (unique index; value is lowercased + trimmed
  on changeset). Links to a host-app user via `user_id` once the
  guest accepts a signup invite.

  Coexists with the inline `guest_*` fields on Ticket for one
  release — a follow-up migration backfills `contact_id` from
  `guest_email`. New code should resolve contacts via
  `find_or_create_by_email/2`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}contacts" do
    field :email, :string
    field :name, :string
    field :user_id, :integer
    field :metadata, :map, default: %{}

    has_many :tickets, Escalated.Schemas.Ticket

    timestamps(type: :utc_datetime)
  end

  # ---------------------------------------------------------------------
  # Pure helpers — used by the service layer without touching the repo
  # and verifiable in plain ExUnit tests.
  # ---------------------------------------------------------------------

  @doc """
  Canonical email normalization: trim surrounding whitespace and
  lowercase. Always call on caller-supplied emails before DB writes.
  """
  @spec normalize_email(String.t() | nil) :: String.t()
  def normalize_email(nil), do: ""
  def normalize_email(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  @doc """
  Decide what `find_or_create_by_email` should do given the
  lookup result and incoming name. Returns one of:

    * `:create` — no existing contact
    * `:update_name` — existing row has a blank name and a non-blank
      name was supplied
    * `:return_existing` — otherwise
  """
  @spec decide_action(map() | struct() | nil, String.t() | nil) ::
          :create | :update_name | :return_existing
  def decide_action(nil, _incoming_name), do: :create
  def decide_action(existing, incoming_name) do
    existing_name = Map.get(existing, :name) || ""
    cond do
      existing_name == "" and is_binary(incoming_name) and incoming_name != "" ->
        :update_name
      true ->
        :return_existing
    end
  end

  # ---------------------------------------------------------------------
  # Changeset
  # ---------------------------------------------------------------------

  @doc false
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:email, :name, :user_id, :metadata])
    |> validate_required([:email])
    |> update_change(:email, &normalize_email/1)
    |> validate_length(:email, max: 320)
    |> unique_constraint(:email)
  end
end
