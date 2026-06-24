defmodule Escalated.Schemas.Article do
  @moduledoc """
  A knowledge-base article. Mirrors the Laravel `Article` model: a unique
  slug (derived from the title when omitted), draft/published status with
  `published_at` stamped on first publish, and view/helpfulness counters.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)
  @statuses ~w(draft published)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}articles" do
    field :category_id, :id
    field :title, :string
    field :slug, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :author_id, @user_id_type
    field :view_count, :integer, default: 0
    field :helpful_count, :integer, default: 0
    field :not_helpful_count, :integer, default: 0
    field :published_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(article, attrs) do
    article
    |> cast(attrs, [
      :category_id,
      :title,
      :slug,
      :body,
      :status,
      :author_id,
      :view_count,
      :helpful_count,
      :not_helpful_count,
      :published_at
    ])
    |> validate_required([:title, :status])
    |> validate_length(:title, max: 255)
    |> validate_inclusion(:status, @statuses)
    |> put_slug()
    |> maybe_published_at()
    |> unique_constraint(:slug)
  end

  def published(query \\ __MODULE__), do: from(a in query, where: a.status == "published")
  def draft(query \\ __MODULE__), do: from(a in query, where: a.status == "draft")

  def search(query \\ __MODULE__, term) do
    pattern = "%#{term}%"
    from(a in query, where: like(a.title, ^pattern) or like(a.body, ^pattern))
  end

  def to_json(%__MODULE__{} = article) do
    %{
      id: article.id,
      category_id: article.category_id,
      title: article.title,
      slug: article.slug,
      body: article.body,
      status: article.status,
      author_id: article.author_id,
      view_count: article.view_count,
      helpful_count: article.helpful_count,
      not_helpful_count: article.not_helpful_count,
      published_at: article.published_at,
      created_at: article.inserted_at,
      updated_at: article.updated_at
    }
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      blank when blank in [nil, ""] ->
        put_change(changeset, :slug, Escalated.Support.Slug.slugify(get_field(changeset, :title)))

      _ ->
        changeset
    end
  end

  defp maybe_published_at(changeset) do
    published? = get_field(changeset, :status) == "published"

    if published? and is_nil(get_field(changeset, :published_at)) do
      put_change(changeset, :published_at, DateTime.utc_now() |> DateTime.truncate(:second))
    else
      changeset
    end
  end
end
