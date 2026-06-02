defmodule Escalated.Schemas.Newsletter.NewsletterList do
  @moduledoc """
  Recipient bucket for a newsletter campaign. `kind = "static"` lists store
  explicit `NewsletterListMember` rows; `kind = "dynamic"` lists hold a saved
  filter JSON evaluated at Plan time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(static dynamic)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}newsletter_lists" do
    field :name, :string
    field :description, :string
    field :kind, :string
    field :filter_json, :map
    field :created_by, :integer

    has_many :members, Escalated.Schemas.Newsletter.NewsletterListMember, foreign_key: :list_id

    timestamps(type: :utc_datetime)
  end

  def changeset(list, attrs) do
    list
    |> cast(attrs, [:name, :description, :kind, :filter_json, :created_by])
    |> validate_required([:name, :kind])
    |> validate_inclusion(:kind, @kinds)
  end
end
