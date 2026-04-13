defmodule Escalated.Schemas.Attachment do
  @moduledoc """
  Ecto schema for file attachments on tickets and replies.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}attachments" do
    field :original_filename, :string
    field :mime_type, :string
    field :size, :integer
    field :storage_key, :string
    field :storage_backend, :string, default: "local"
    field :uploaded_by, :integer

    belongs_to :ticket, Escalated.Schemas.Ticket
    belongs_to :reply, Escalated.Schemas.Reply

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [
      :original_filename, :mime_type, :size, :storage_key,
      :storage_backend, :ticket_id, :reply_id, :uploaded_by
    ])
    |> validate_required([:original_filename, :storage_key])
    |> validate_number(:size, greater_than: 0)
  end

  @doc """
  Builds a public URL for the attachment.

  Uses the configured route prefix to construct the download path.
  """
  def url(%__MODULE__{} = attachment) do
    prefix = Application.get_env(:escalated, :route_prefix, "/support")
    "#{prefix}/attachments/#{attachment.id}/download"
  end
end
