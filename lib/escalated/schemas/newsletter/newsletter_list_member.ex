defmodule Escalated.Schemas.Newsletter.NewsletterListMember do
  use Ecto.Schema
  import Ecto.Changeset
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}newsletter_list_members" do
    field :list_id, :integer
    field :contact_id, :integer
    field :added_at, :utc_datetime
    field :added_by, @user_id_type
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:list_id, :contact_id, :added_at, :added_by])
    |> validate_required([:list_id, :contact_id])
    |> unique_constraint([:list_id, :contact_id])
  end
end
