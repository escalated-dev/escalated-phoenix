defmodule Escalated.Services.Email.Inbound.ParserEquivalenceTest do
  @moduledoc """
  Parser-equivalence tests: the same logical email, expressed in each
  provider's native webhook payload shape, should normalize to the
  same `Escalated.Services.Email.Inbound.Message` metadata. Parser
  equivalence at this layer guarantees a reply delivered via any
  provider routes to the same ticket via the same threading chain.

  Mirrors escalated-go#37 + escalated-dotnet#31 + escalated-spring#34.
  Adding a fourth provider in the future can reuse the same
  `logical_email/0` + `*_payload/1` builders and get contract
  validation for free.
  """

  use ExUnit.Case, async: true

  alias Escalated.Services.Email.Inbound.{
    MailgunParser,
    PostmarkParser,
    SESParser
  }

  @sample %{
    from_email: "alice@example.com",
    from_name: "Alice",
    to_email: "support@example.com",
    subject: "Re: Help with invoice",
    body_text: "Thanks for the quick response.",
    message_id: "<external-reply-xyz@mail.alice.com>",
    in_reply_to: "<ticket-42@support.example.com>",
    references: "<ticket-42@support.example.com>"
  }

  defp postmark_payload(e) do
    %{
      "FromFull" => %{"Email" => e.from_email, "Name" => e.from_name},
      "To" => e.to_email,
      "Subject" => e.subject,
      "TextBody" => e.body_text,
      "Headers" => [
        %{"Name" => "Message-ID", "Value" => e.message_id},
        %{"Name" => "In-Reply-To", "Value" => e.in_reply_to},
        %{"Name" => "References", "Value" => e.references}
      ]
    }
  end

  defp mailgun_payload(e) do
    %{
      "sender" => e.from_email,
      "from" => "#{e.from_name} <#{e.from_email}>",
      "recipient" => e.to_email,
      "subject" => e.subject,
      "body-plain" => e.body_text,
      "Message-Id" => e.message_id,
      "In-Reply-To" => e.in_reply_to,
      "References" => e.references
    }
  end

  defp ses_payload(e) do
    # Include full raw MIME as base64 so body extraction is exercised
    # — keeps the payload close to a real SES delivery.
    mime =
      "From: #{e.from_name} <#{e.from_email}>\r\n" <>
        "To: #{e.to_email}\r\n" <>
        "Subject: #{e.subject}\r\n" <>
        "Message-ID: #{e.message_id}\r\n" <>
        "In-Reply-To: #{e.in_reply_to}\r\n" <>
        "References: #{e.references}\r\n" <>
        "Content-Type: text/plain; charset=\"utf-8\"\r\n" <>
        "\r\n" <>
        e.body_text

    ses_message = %{
      "notificationType" => "Received",
      "mail" => %{
        "source" => e.from_email,
        "destination" => [e.to_email],
        "headers" => [
          %{"name" => "From", "value" => "#{e.from_name} <#{e.from_email}>"},
          %{"name" => "To", "value" => e.to_email},
          %{"name" => "Subject", "value" => e.subject},
          %{"name" => "Message-ID", "value" => e.message_id},
          %{"name" => "In-Reply-To", "value" => e.in_reply_to},
          %{"name" => "References", "value" => e.references}
        ],
        "commonHeaders" => %{
          "from" => ["#{e.from_name} <#{e.from_email}>"],
          "to" => [e.to_email],
          "subject" => e.subject
        }
      },
      "content" => Base.encode64(mime)
    }

    %{
      "Type" => "Notification",
      "Message" => Jason.encode!(ses_message)
    }
  end

  describe "normalizes to same message" do
    test "threading metadata matches across Postmark / Mailgun / SES" do
      {:ok, postmark} = PostmarkParser.parse(postmark_payload(@sample))
      {:ok, mailgun} = MailgunParser.parse(mailgun_payload(@sample))
      {:ok, ses} = SESParser.parse(ses_payload(@sample))

      for {name, msg} <- [{"postmark", postmark}, {"mailgun", mailgun}, {"ses", ses}] do
        assert msg.from_email == @sample.from_email, "#{name}: from_email mismatch"
        assert msg.to_email == @sample.to_email, "#{name}: to_email mismatch"
        assert msg.subject == @sample.subject, "#{name}: subject mismatch"
        assert msg.in_reply_to == @sample.in_reply_to, "#{name}: in_reply_to mismatch"
        assert msg.references == @sample.references, "#{name}: references mismatch"
      end
    end
  end

  describe "body extraction matches" do
    test "body_text matches across all three parsers" do
      {:ok, postmark} = PostmarkParser.parse(postmark_payload(@sample))
      {:ok, mailgun} = MailgunParser.parse(mailgun_payload(@sample))
      {:ok, ses} = SESParser.parse(ses_payload(@sample))

      assert postmark.body_text == @sample.body_text
      assert mailgun.body_text == @sample.body_text
      assert ses.body_text == @sample.body_text
    end
  end
end
