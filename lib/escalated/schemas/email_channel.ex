defmodule Escalated.Schemas.EmailChannel do
  @moduledoc """
  Ecto schema for email channel configuration per department with DKIM validation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}email_channels" do
    field :email_address, :string
    field :display_name, :string
    field :is_default, :boolean, default: false
    field :is_verified, :boolean, default: false
    field :dkim_status, :string, default: "pending"
    field :dkim_public_key, :string
    field :dkim_selector, :string
    field :reply_to_address, :string
    field :smtp_protocol, :string, default: "tls"
    field :smtp_host, :string
    field :smtp_port, :integer
    field :smtp_username, :string
    field :smtp_password, :string
    field :is_active, :boolean, default: true

    belongs_to :department, Escalated.Schemas.Department

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(email_channel, attrs) do
    email_channel
    |> cast(attrs, [
      :email_address, :display_name, :department_id, :is_default, :is_verified,
      :dkim_status, :dkim_public_key, :dkim_selector, :reply_to_address,
      :smtp_protocol, :smtp_host, :smtp_port, :smtp_username, :smtp_password, :is_active
    ])
    |> validate_required([:email_address])
    |> validate_format(:email_address, ~r/@/, message: "must be a valid email")
    |> unique_constraint(:email_address)
  end

  def formatted_sender(%__MODULE__{display_name: nil, email_address: addr}), do: addr
  def formatted_sender(%__MODULE__{display_name: name, email_address: addr}), do: "#{name} <#{addr}>"
end
