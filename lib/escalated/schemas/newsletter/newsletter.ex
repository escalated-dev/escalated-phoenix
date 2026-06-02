defmodule Escalated.Schemas.Newsletter.Newsletter do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft scheduled sending sent paused failed)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}newsletters" do
    field :subject, :string
    field :from_email, :string
    field :from_name, :string
    field :reply_to, :string
    field :target_list_id, :integer
    field :template_id, :integer
    field :theme, :string
    field :body_markdown, :string
    field :status, :string, default: "draft"
    field :scheduled_at, :utc_datetime
    field :sent_at, :utc_datetime
    field :created_by, :integer
    field :sent_by, :integer
    field :summary_total, :integer, default: 0
    field :summary_sent, :integer, default: 0
    field :summary_opened, :integer, default: 0
    field :summary_clicked, :integer, default: 0
    field :summary_bounced, :integer, default: 0
    field :summary_complained, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(newsletter, attrs) do
    newsletter
    |> cast(attrs, [
      :subject,
      :from_email,
      :from_name,
      :reply_to,
      :target_list_id,
      :template_id,
      :theme,
      :body_markdown,
      :status,
      :scheduled_at,
      :sent_at,
      :created_by,
      :sent_by,
      :summary_total,
      :summary_sent,
      :summary_opened,
      :summary_clicked,
      :summary_bounced,
      :summary_complained
    ])
    |> validate_required([:subject, :from_email, :target_list_id, :status])
    |> validate_inclusion(:status, @statuses)
  end
end
