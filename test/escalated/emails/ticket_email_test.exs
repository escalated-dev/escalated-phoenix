defmodule Escalated.Emails.TicketEmailTest do
  use ExUnit.Case, async: true

  alias Escalated.Emails.TicketEmail
  alias Escalated.Schemas.{Ticket, Reply}

  @ticket %Ticket{
    id: 1,
    reference: "ESC-2604-ABC123",
    subject: "Login not working",
    description: "I cannot log in to my account.",
    status: "open",
    priority: "medium"
  }

  @reply %Reply{
    id: 42,
    body: "We are looking into this issue.",
    ticket_id: 1,
    author_id: 5
  }

  describe "branding/0" do
    test "returns default branding when not configured" do
      brand = TicketEmail.branding()
      assert brand.company_name == "Support"
      assert brand.accent_color == "#4F46E5"
      assert brand.footer_text == "Powered by Escalated"
      assert brand.logo_url == nil
    end
  end

  describe "message_id_for_ticket/1" do
    test "generates a stable message ID with ticket reference" do
      mid = TicketEmail.message_id_for_ticket(@ticket)
      assert mid =~ "escalated-ESC-2604-ABC123@"
      assert String.starts_with?(mid, "<")
      assert String.ends_with?(mid, ">")
    end

    test "same ticket always produces the same message ID" do
      mid1 = TicketEmail.message_id_for_ticket(@ticket)
      mid2 = TicketEmail.message_id_for_ticket(@ticket)
      assert mid1 == mid2
    end
  end

  describe "message_id_for_reply/2" do
    test "includes ticket reference and reply ID" do
      mid = TicketEmail.message_id_for_reply(@ticket, @reply)
      assert mid =~ "escalated-ESC-2604-ABC123-42@"
      assert String.starts_with?(mid, "<")
      assert String.ends_with?(mid, ">")
    end

    test "different replies produce different message IDs" do
      reply2 = %Reply{@reply | id: 43}
      mid1 = TicketEmail.message_id_for_reply(@ticket, @reply)
      mid2 = TicketEmail.message_id_for_reply(@ticket, reply2)
      refute mid1 == mid2
    end
  end

  describe "threading_headers_for_ticket/1" do
    test "returns only Message-ID header" do
      headers = TicketEmail.threading_headers_for_ticket(@ticket)
      assert length(headers) == 1
      assert {"Message-ID", _} = hd(headers)
    end
  end

  describe "threading_headers_for_reply/2" do
    test "returns Message-ID, In-Reply-To, and References headers" do
      headers = TicketEmail.threading_headers_for_reply(@ticket, @reply)
      header_names = Enum.map(headers, fn {name, _} -> name end)

      assert "Message-ID" in header_names
      assert "In-Reply-To" in header_names
      assert "References" in header_names
    end

    test "In-Reply-To points to the ticket message ID" do
      ticket_mid = TicketEmail.message_id_for_ticket(@ticket)
      headers = TicketEmail.threading_headers_for_reply(@ticket, @reply) |> Map.new()

      assert headers["In-Reply-To"] == ticket_mid
    end

    test "References points to the ticket message ID" do
      ticket_mid = TicketEmail.message_id_for_ticket(@ticket)
      headers = TicketEmail.threading_headers_for_reply(@ticket, @reply) |> Map.new()

      assert headers["References"] == ticket_mid
    end

    test "Message-ID is the reply message ID" do
      reply_mid = TicketEmail.message_id_for_reply(@ticket, @reply)
      headers = TicketEmail.threading_headers_for_reply(@ticket, @reply) |> Map.new()

      assert headers["Message-ID"] == reply_mid
    end
  end

  describe "new_ticket_email/3" do
    test "builds email with correct subject including reference" do
      email = TicketEmail.new_ticket_email(@ticket, "user@example.com")
      assert email.subject == "[ESC-2604-ABC123] Login not working"
    end

    test "builds email with threading headers" do
      email = TicketEmail.new_ticket_email(@ticket, "user@example.com")
      assert Map.has_key?(email.headers, "Message-ID")
    end

    test "builds email with HTML body containing ticket description" do
      email = TicketEmail.new_ticket_email(@ticket, "user@example.com")
      assert email.html_body =~ "I cannot log in to my account."
      assert email.html_body =~ "ESC-2604-ABC123"
    end

    test "builds email with text body" do
      email = TicketEmail.new_ticket_email(@ticket, "user@example.com")
      assert email.text_body =~ "I cannot log in to my account."
    end

    test "includes branding footer in HTML" do
      email = TicketEmail.new_ticket_email(@ticket, "user@example.com")
      assert email.html_body =~ "Powered by Escalated"
    end

    test "allows subject override" do
      email = TicketEmail.new_ticket_email(@ticket, "user@example.com", subject: "Custom subject")
      assert email.subject == "Custom subject"
    end
  end

  describe "reply_email/4" do
    test "builds email with Re: prefix in subject" do
      email = TicketEmail.reply_email(@ticket, @reply, "user@example.com")
      assert email.subject == "Re: [ESC-2604-ABC123] Login not working"
    end

    test "builds email with In-Reply-To header" do
      email = TicketEmail.reply_email(@ticket, @reply, "user@example.com")
      assert Map.has_key?(email.headers, "In-Reply-To")
    end

    test "builds email with reply body in HTML" do
      email = TicketEmail.reply_email(@ticket, @reply, "user@example.com")
      assert email.html_body =~ "We are looking into this issue."
    end

    test "builds email with reply body in text" do
      email = TicketEmail.reply_email(@ticket, @reply, "user@example.com")
      assert email.text_body =~ "We are looking into this issue."
    end
  end
end
