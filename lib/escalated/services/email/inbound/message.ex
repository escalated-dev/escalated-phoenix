defmodule Escalated.Services.Email.Inbound.Message do
  @moduledoc """
  Transport-agnostic representation of an inbound email, independent
  of the source adapter (Postmark, Mailgun, SES, IMAP, etc.).

  Adapters normalize their provider-specific webhook payload into this
  shape; `Escalated.Services.Email.Inbound.Router` then maps it to an
  existing ticket via canonical Message-ID parsing + signed Reply-To
  verification.
  """

  @enforce_keys [:from_email, :to_email, :subject]
  defstruct [
    :from_email,
    :from_name,
    :to_email,
    :subject,
    :body_text,
    :body_html,
    :message_id,
    :in_reply_to,
    :references,
    headers: %{},
    attachments: []
  ]

  @type t :: %__MODULE__{
          from_email: String.t(),
          from_name: String.t() | nil,
          to_email: String.t(),
          subject: String.t(),
          body_text: String.t() | nil,
          body_html: String.t() | nil,
          message_id: String.t() | nil,
          in_reply_to: String.t() | nil,
          references: String.t() | nil,
          headers: map(),
          attachments: list()
        }

  @doc """
  Best body content — plain text preferred, HTML fallback.
  """
  @spec body(t()) :: String.t()
  def body(%__MODULE__{body_text: text}) when is_binary(text) and text != "", do: text
  def body(%__MODULE__{body_html: html}) when is_binary(html), do: html
  def body(_), do: ""
end
