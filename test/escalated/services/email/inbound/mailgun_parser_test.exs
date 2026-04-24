defmodule Escalated.Services.Email.Inbound.MailgunParserTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.Email.Inbound.MailgunParser

  @sample_payload %{
    "sender" => "customer@example.com",
    "from" => "Customer <customer@example.com>",
    "recipient" => "support+abc@support.example.com",
    "To" => "support+abc@support.example.com",
    "subject" => "[ESC-00042] Help",
    "body-plain" => "Plain body",
    "body-html" => "<p>HTML body</p>",
    "Message-Id" => "<mailgun-incoming@mail.client>",
    "In-Reply-To" => "<ticket-42@support.example.com>",
    "References" => "<ticket-42@support.example.com>",
    "attachments" =>
      ~s([{"name":"report.pdf","content-type":"application/pdf","size":5120,"url":"https://mailgun.example/att/abc"}])
  }

  test "name/0 is mailgun" do
    assert MailgunParser.name() == "mailgun"
  end

  test "parse/1 extracts core fields" do
    assert {:ok, m} = MailgunParser.parse(@sample_payload)
    assert m.from_email == "customer@example.com"
    assert m.from_name == "Customer"
    assert m.to_email == "support+abc@support.example.com"
    assert m.subject == "[ESC-00042] Help"
    assert m.body_text == "Plain body"
    assert m.body_html == "<p>HTML body</p>"
  end

  test "parse/1 extracts threading headers" do
    assert {:ok, m} = MailgunParser.parse(@sample_payload)
    assert m.in_reply_to == "<ticket-42@support.example.com>"
    assert m.references == "<ticket-42@support.example.com>"
  end

  test "parse/1 extracts provider-hosted attachments with download URL" do
    assert {:ok, m} = MailgunParser.parse(@sample_payload)
    assert [attachment] = m.attachments
    assert attachment.name == "report.pdf"
    assert attachment.content_type == "application/pdf"
    assert attachment.size_bytes == 5120
    assert attachment.download_url == "https://mailgun.example/att/abc"
    # Mailgun hosts content — no inline bytes.
    assert attachment.content == nil
  end

  test "parse/1 handles malformed attachments JSON gracefully" do
    payload = Map.put(@sample_payload, "attachments", "not json")
    assert {:ok, m} = MailgunParser.parse(payload)
    assert m.attachments == []
  end

  test "parse/1 falls back sender→from when sender missing" do
    payload = %{
      "from" => "only-from@example.com",
      "recipient" => "support@example.com",
      "subject" => "hi"
    }

    assert {:ok, m} = MailgunParser.parse(payload)
    assert m.from_email == "only-from@example.com"
  end

  test "parse/1 returns nil from_name for bare email (no angle brackets)" do
    payload = %{
      "sender" => "bareemail@example.com",
      "from" => "bareemail@example.com",
      "recipient" => "support@example.com",
      "subject" => "hi"
    }

    assert {:ok, m} = MailgunParser.parse(payload)
    assert m.from_name == nil
  end

  test "parse/1 strips quotes from display name" do
    payload = %{
      "sender" => "jane@example.com",
      "from" => ~s("Jane Doe" <jane@example.com>),
      "recipient" => "support@example.com",
      "subject" => "hi"
    }

    assert {:ok, m} = MailgunParser.parse(payload)
    assert m.from_name == "Jane Doe"
  end

  test "parse/1 rejects non-map payload" do
    assert {:error, :unsupported_payload} = MailgunParser.parse("not a map")
    assert {:error, :unsupported_payload} = MailgunParser.parse(42)
    assert {:error, :unsupported_payload} = MailgunParser.parse(nil)
  end
end
