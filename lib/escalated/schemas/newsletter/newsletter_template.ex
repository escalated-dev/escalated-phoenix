defmodule Escalated.Schemas.Newsletter.NewsletterTemplate do
  use Ecto.Schema
  import Ecto.Changeset
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}newsletter_templates" do
    field :name, :string
    field :theme, :string, default: "default"
    field :subject_template, :string
    field :body_markdown, :string
    field :merge_fields_schema, :map
    field :created_by, @user_id_type

    timestamps(type: :utc_datetime)
  end

  def changeset(tpl, attrs) do
    tpl
    |> cast(attrs, [
      :name,
      :theme,
      :subject_template,
      :body_markdown,
      :merge_fields_schema,
      :created_by
    ])
    |> validate_required([:name, :theme, :body_markdown])
  end
end
