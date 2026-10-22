defmodule Escalated.Schemas.ApiToken do
  @moduledoc """
  An API token, as escalated-laravel's `ApiToken`: it lets an integration call
  the JSON ticket API as its owner (a host user), within its abilities
  (`agent`, `admin`, or `*` for both).

  Only the SHA-256 digest of the token is stored (`token`); the plain text is
  shown once, when the token is created (`Escalated.Services.ApiTokenService`).
  The digest is redacted from `inspect/1` and never sent to a page.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)
  @abilities ~w(agent admin *)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}api_tokens" do
    field :tenant_id, :string, default: ""
    field :user_id, @user_id_type
    field :name, :string
    field :token, :string, redact: true
    field :abilities, {:array, :string}, default: []
    field :last_used_at, :utc_datetime
    field :last_used_ip, :string
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc "The abilities a token can carry."
  def abilities, do: @abilities

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :name, :token, :abilities, :expires_at])
    |> validate_required([:user_id, :name, :token, :abilities])
    |> update_changeset(%{})
    |> unique_constraint(:token)
    |> Escalated.Tenancy.Constraints.add_unique_constraints()
  end

  @doc "What an admin may change on an existing token: its name and abilities."
  def update_changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :abilities])
    |> validate_required([:name, :abilities])
    |> validate_length(:name, max: 255)
    |> validate_length(:abilities, min: 1)
    |> validate_subset(:abilities, @abilities)
  end

  @doc "Whether `token` grants `ability` (`*` grants every ability)."
  def has_ability?(%__MODULE__{abilities: abilities}, ability) do
    abilities = abilities || []
    "*" in abilities or ability in abilities
  end

  @doc "Whether `token` has expired."
  def expired?(%__MODULE__{expires_at: nil}), do: false

  def expired?(%__MODULE__{expires_at: expires_at}),
    do: DateTime.compare(expires_at, DateTime.utc_now()) != :gt
end
