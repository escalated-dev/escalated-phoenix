defmodule Escalated.Schemas.Department do
  @moduledoc """
  Ecto schema for support departments / teams.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}departments" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :email, :string
    field :is_active, :boolean, default: true

    belongs_to :default_sla_policy, Escalated.Schemas.SlaPolicy

    has_many :tickets, Escalated.Schemas.Ticket

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(department, attrs) do
    department
    |> cast(attrs, [:name, :slug, :description, :email, :is_active, :default_sla_policy_id])
    |> validate_required([:name])
    |> validate_format(:email, ~r/@/, message: "must be a valid email")
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
    |> maybe_generate_slug()
  end

  def active(query \\ __MODULE__) do
    from(d in query, where: d.is_active == true)
  end

  def ordered(query \\ __MODULE__) do
    from(d in query, order_by: [asc: d.name])
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""
        slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end
