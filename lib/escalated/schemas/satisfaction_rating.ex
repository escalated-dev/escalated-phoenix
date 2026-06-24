defmodule Escalated.Schemas.SatisfactionRating do
  @moduledoc """
  Ecto schema for CSAT (customer satisfaction) ratings.

  One rating per ticket, submitted only once a ticket is resolved or
  closed. Mirrors the Laravel `SatisfactionRating` model (no `updated_at`;
  `created_at` is stamped on insert). `rated_by_*` is an optional
  polymorphic reference to the rater (absent for guest submissions).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}satisfaction_ratings" do
    field :rating, :integer
    field :comment, :string
    field :rated_by_type, :string
    field :rated_by_id, @user_id_type
    field :created_at, :utc_datetime

    belongs_to :ticket, Escalated.Schemas.Ticket
  end

  @doc false
  def changeset(rating, attrs) do
    rating
    |> cast(attrs, [:ticket_id, :rating, :comment, :rated_by_type, :rated_by_id, :created_at])
    |> validate_required([:ticket_id, :rating])
    |> validate_inclusion(:rating, 1..5)
    |> validate_length(:comment, max: 2000)
    |> maybe_put_created_at()
    |> unique_constraint(:ticket_id)
  end

  defp maybe_put_created_at(changeset) do
    case get_field(changeset, :created_at) do
      nil -> put_change(changeset, :created_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  @doc "Serialize a rating row for the admin/reporting frontend."
  def to_json(%__MODULE__{} = r) do
    %{
      id: r.id,
      ticket_id: r.ticket_id,
      rating: r.rating,
      comment: r.comment,
      rated_by_type: r.rated_by_type,
      rated_by_id: r.rated_by_id,
      created_at: r.created_at
    }
  end
end
