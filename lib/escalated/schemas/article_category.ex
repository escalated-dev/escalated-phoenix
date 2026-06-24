defmodule Escalated.Schemas.ArticleCategory do
  @moduledoc """
  A knowledge-base article category (optionally hierarchical via
  `parent_id`). Mirrors the Laravel `ArticleCategory` model.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}article_categories" do
    field :name, :string
    field :slug, :string
    field :parent_id, :id
    field :position, :integer, default: 0
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :parent_id, :position, :description])
    |> validate_required([:name])
    |> put_slug(:name)
    |> unique_constraint(:slug)
  end

  def roots(query \\ __MODULE__), do: from(c in query, where: is_nil(c.parent_id))

  def ordered(query \\ __MODULE__),
    do: from(c in query, order_by: [asc: c.position, asc: c.name])

  def to_json(%__MODULE__{} = category) do
    %{
      id: category.id,
      name: category.name,
      slug: category.slug,
      parent_id: category.parent_id,
      position: category.position,
      description: category.description
    }
  end

  defp put_slug(changeset, source) do
    case get_field(changeset, :slug) do
      blank when blank in [nil, ""] ->
        put_change(changeset, :slug, Escalated.Support.Slug.slugify(get_field(changeset, source)))

      _ ->
        changeset
    end
  end
end
