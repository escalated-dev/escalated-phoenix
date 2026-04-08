defmodule Escalated.Emails.TicketEmail do
  @moduledoc """
  Builds Swoosh email structs for ticket notifications with proper
  threading headers (Message-ID, In-Reply-To, References) and
  configurable branding.

  ## Threading

  Each ticket gets a stable Message-ID based on its reference. Replies
  include `In-Reply-To` and `References` headers so email clients group
  them into a single conversation thread.

  ## Branding

  Branding is read from application config:

      config :escalated,
        email_branding: %{
          company_name: "Acme Support",
          logo_url: "https://example.com/logo.png",
          accent_color: "#4F46E5",
          footer_text: "Powered by Escalated"
        }
  """

  @doc """
  Returns the configured email branding settings merged with defaults.
  """
  def branding do
    defaults = %{
      company_name: "Support",
      logo_url: nil,
      accent_color: "#4F46E5",
      footer_text: "Powered by Escalated"
    }

    configured = Escalated.config(:email_branding, %{})

    Map.merge(defaults, configured)
  end

  @doc """
  Generates a stable Message-ID for a ticket.

  Format: `<escalated-REFERENCE@DOMAIN>`
  """
  def message_id_for_ticket(ticket) do
    domain = email_domain()
    "<escalated-#{ticket.reference}@#{domain}>"
  end

  @doc """
  Generates a Message-ID for a specific reply on a ticket.

  Format: `<escalated-REFERENCE-REPLY_ID@DOMAIN>`
  """
  def message_id_for_reply(ticket, reply) do
    domain = email_domain()
    "<escalated-#{ticket.reference}-#{reply.id}@#{domain}>"
  end

  @doc """
  Returns threading headers for a new ticket notification email.

  Only sets `Message-ID`.
  """
  def threading_headers_for_ticket(ticket) do
    [
      {"Message-ID", message_id_for_ticket(ticket)}
    ]
  end

  @doc """
  Returns threading headers for a reply notification email.

  Sets `Message-ID`, `In-Reply-To`, and `References` so clients thread
  the reply under the original ticket email.
  """
  def threading_headers_for_reply(ticket, reply) do
    ticket_mid = message_id_for_ticket(ticket)
    reply_mid = message_id_for_reply(ticket, reply)

    [
      {"Message-ID", reply_mid},
      {"In-Reply-To", ticket_mid},
      {"References", ticket_mid}
    ]
  end

  @doc """
  Builds a base Swoosh.Email struct with branding and threading for a new ticket.
  """
  def new_ticket_email(ticket, to, opts \\ []) do
    brand = branding()
    subject = Keyword.get(opts, :subject, "[#{ticket.reference}] #{ticket.subject}")

    %{
      to: to,
      from: from_address(brand),
      subject: subject,
      headers: threading_headers_for_ticket(ticket) |> Map.new(),
      html_body: render_html(:new_ticket, %{ticket: ticket, branding: brand}),
      text_body: render_text(:new_ticket, %{ticket: ticket, branding: brand})
    }
  end

  @doc """
  Builds a base Swoosh.Email struct with branding and threading for a reply.
  """
  def reply_email(ticket, reply, to, opts \\ []) do
    brand = branding()
    subject = Keyword.get(opts, :subject, "Re: [#{ticket.reference}] #{ticket.subject}")

    %{
      to: to,
      from: from_address(brand),
      subject: subject,
      headers: threading_headers_for_reply(ticket, reply) |> Map.new(),
      html_body: render_html(:reply, %{ticket: ticket, reply: reply, branding: brand}),
      text_body: render_text(:reply, %{ticket: ticket, reply: reply, branding: brand})
    }
  end

  # Private

  defp email_domain do
    Escalated.config(:email_domain, "escalated.localhost")
  end

  defp from_address(brand) do
    from_email = Escalated.config(:from_email, "support@#{email_domain()}")
    {brand.company_name, from_email}
  end

  defp render_html(:new_ticket, assigns) do
    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"></head>
    <body style="font-family: -apple-system, sans-serif; margin: 0; padding: 0;">
      <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        #{logo_html(assigns.branding)}
        <h2 style="color: #{assigns.branding.accent_color};">[#{assigns.ticket.reference}] #{assigns.ticket.subject}</h2>
        <div style="padding: 16px; background: #f9fafb; border-radius: 8px; margin: 16px 0;">
          #{assigns.ticket.description}
        </div>
        <p style="color: #6b7280; font-size: 12px;">#{assigns.branding.footer_text}</p>
      </div>
    </body>
    </html>
    """
  end

  defp render_html(:reply, assigns) do
    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"></head>
    <body style="font-family: -apple-system, sans-serif; margin: 0; padding: 0;">
      <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
        #{logo_html(assigns.branding)}
        <h2 style="color: #{assigns.branding.accent_color};">Re: [#{assigns.ticket.reference}] #{assigns.ticket.subject}</h2>
        <div style="padding: 16px; background: #f9fafb; border-radius: 8px; margin: 16px 0;">
          #{assigns.reply.body}
        </div>
        <p style="color: #6b7280; font-size: 12px;">#{assigns.branding.footer_text}</p>
      </div>
    </body>
    </html>
    """
  end

  defp render_text(:new_ticket, assigns) do
    """
    [#{assigns.ticket.reference}] #{assigns.ticket.subject}

    #{assigns.ticket.description}

    --
    #{assigns.branding.footer_text}
    """
  end

  defp render_text(:reply, assigns) do
    """
    Re: [#{assigns.ticket.reference}] #{assigns.ticket.subject}

    #{assigns.reply.body}

    --
    #{assigns.branding.footer_text}
    """
  end

  defp logo_html(%{logo_url: nil}), do: ""

  defp logo_html(%{logo_url: url}) do
    ~s(<img src="#{url}" alt="Logo" style="max-height: 40px; margin-bottom: 16px;" />)
  end
end
