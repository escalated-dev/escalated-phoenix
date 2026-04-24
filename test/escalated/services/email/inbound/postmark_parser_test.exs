defmodule Escalated.Services.Email.Inbound.PostmarkParserTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.Email.Inbound.PostmarkParser

  @sample_payload %{
    "FromName" => "Customer",
    "MessageID" => "22c74902-a0c1-4511-804f2-341342852c90",
    "FromFull" => %{"Email" => "customer@example.com", "Name" => "Customer"},
    "To" => "support+abc@support.example.com",
    "ToFull" => [%{"Email" => "support+abc@support.example.com", "Name" => ""}],
    "OriginalRecipient" => "support+abc@support.example.com",
    "Subject" => "[ESC-00042] Help",
    "TextBody" => "Plain body",
    "HtmlBody" => "<p>HTML body</p>",
    "Headers" => [
      %{"Name" => "Message-ID", "Value" => "<abc@mail.client>"},
      %{"Name" => "In-Reply-To", "Value" => "<ticket-42@support.example.com>"},
      %{"Name" => "References", "Value" => "<ticket-42@support.example.com>"}
    ],
    "Attachments" => [
      %{
        "Name" => "report.pdf",
        "Content" => "aGVsbG8=",
        "ContentType" => "application/pdf",
        "ContentLength" => 5
      }
    ]
  }

  test "name/0 is postmark" do
    assert PostmarkParser.name() == "postmark"
  end

  test "parse/1 extracts core fields" do
    assert {:ok, m} = PostmarkParser.parse(@sample_payload)
    assert m.from_email == "customer@example.com"
    assert m.from_name == "Customer"
    assert m.to_email == "support+abc@support.example.com"
    assert m.subject == "[ESC-00042] Help"
    assert m.body_text == "Plain body"
    assert m.body_html == "<p>HTML body</p>"
  end

  test "parse/1 extracts threading headers from Headers array" do
    assert {:ok, m} = PostmarkParser.parse(@sample_payload)
    assert m.in_reply_to == "<ticket-42@support.example.com>"
    assert m.references == "<ticket-42@support.example.com>"
  end

  test "parse/1 decodes base64 attachment content" do
    assert {:ok, m} = PostmarkParser.parse(@sample_payload)
    assert [attachment] = m.attachments
    assert attachment.name == "report.pdf"
    assert attachment.content_type == "application/pdf"
    assert attachment.size_bytes == 5
    assert attachment.content == "hello"
  end

  test "parse/1 handles minimal payload" do
    payload = %{
      "FromFull" => %{"Email" => "a@b.com"},
      "ToFull" => [%{"Email" => "c@d.com"}],
      "Subject" => "minimal"
    }

    assert {:ok, m} = PostmarkParser.parse(payload)
    assert m.from_email == "a@b.com"
    assert m.from_name == nil
    assert m.to_email == "c@d.com"
    assert m.subject == "minimal"
    assert m.body_text == nil
    assert m.in_reply_to == nil
    assert m.attachments == []
  end

  test "parse/1 rejects non-map payload" do
    assert {:error, :unsupported_payload} = PostmarkParser.parse("not a map")
    assert {:error, :unsupported_payload} = PostmarkParser.parse(42)
    assert {:error, :unsupported_payload} = PostmarkParser.parse(nil)
  end
end
