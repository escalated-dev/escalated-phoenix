defmodule Escalated.Services.Email.Inbound.SESParserTest do
  use ExUnit.Case, async: true

  alias Escalated.Services.Email.Inbound.SESParser

  describe "name/0" do
    test "returns \"ses\"" do
      assert SESParser.name() == "ses"
    end
  end

  describe "subscription confirmation" do
    test "returns a structured sentinel error with the subscribe URL" do
      envelope = %{
        "Type" => "SubscriptionConfirmation",
        "TopicArn" => "arn:aws:sns:us-east-1:123:escalated-inbound",
        "SubscribeURL" =>
          "https://sns.us-east-1.amazonaws.com/?Action=ConfirmSubscription&Token=x",
        "Token" => "abc"
      }

      assert {:error, {:ses_subscription_confirmation, details}} = SESParser.parse(envelope)
      assert details.topic_arn == "arn:aws:sns:us-east-1:123:escalated-inbound"
      assert details.subscribe_url =~ "ConfirmSubscription"
      assert details.token == "abc"
    end
  end

  describe "notification" do
    test "extracts full threading metadata from commonHeaders + headers" do
      envelope = notification_envelope(%{
        "mail" => %{
          "source" => "alice@example.com",
          "destination" => ["support@example.com"],
          "headers" => [
            %{"name" => "From", "value" => "Alice <alice@example.com>"},
            %{"name" => "To", "value" => "support@example.com"},
            %{"name" => "Subject", "value" => "[ESC-42] Re: Help"},
            %{"name" => "Message-ID", "value" => "<external-xyz@mail.alice.com>"},
            %{"name" => "In-Reply-To", "value" => "<ticket-42@support.example.com>"},
            %{"name" => "References",
              "value" => "<ticket-42@support.example.com> <prev@mail.com>"}
          ],
          "commonHeaders" => %{
            "from" => ["Alice <alice@example.com>"],
            "to" => ["support@example.com"],
            "subject" => "[ESC-42] Re: Help"
          }
        }
      })

      assert {:ok, msg} = SESParser.parse(envelope)
      assert msg.from_email == "alice@example.com"
      assert msg.from_name == "Alice"
      assert msg.to_email == "support@example.com"
      assert msg.subject == "[ESC-42] Re: Help"
      assert msg.message_id == "<external-xyz@mail.alice.com>"
      assert msg.in_reply_to == "<ticket-42@support.example.com>"
      assert msg.references =~ "ticket-42@support.example.com"
      assert msg.headers["From"] == "Alice <alice@example.com>"
    end

    test "decodes plain text body from base64 MIME content" do
      raw_mime = """
      From: alice@example.com\r
      To: support@example.com\r
      Subject: Hi\r
      Content-Type: text/plain; charset="utf-8"\r
      \r
      This is the plain text body.\
      """

      envelope =
        notification_envelope(%{
          "mail" => %{
            "commonHeaders" => %{
              "from" => ["alice@example.com"],
              "to" => ["support@example.com"],
              "subject" => "Hi"
            }
          },
          "content" => Base.encode64(raw_mime)
        })

      assert {:ok, msg} = SESParser.parse(envelope)
      assert msg.body_text =~ "plain text body"
    end

    test "decodes multipart/alternative bodies" do
      boundary = "boundary-abc"

      raw_mime =
        "From: alice@example.com\r\n" <>
          "To: support@example.com\r\n" <>
          "Subject: Hi\r\n" <>
          "Content-Type: multipart/alternative; boundary=\"#{boundary}\"\r\n" <>
          "\r\n" <>
          "--#{boundary}\r\n" <>
          "Content-Type: text/plain; charset=\"utf-8\"\r\n" <>
          "\r\n" <>
          "Plain body\r\n" <>
          "--#{boundary}\r\n" <>
          "Content-Type: text/html; charset=\"utf-8\"\r\n" <>
          "\r\n" <>
          "<p>HTML body</p>\r\n" <>
          "--#{boundary}--\r\n"

      envelope =
        notification_envelope(%{
          "mail" => %{
            "commonHeaders" => %{
              "from" => ["alice@example.com"],
              "to" => ["support@example.com"],
              "subject" => "Hi"
            }
          },
          "content" => Base.encode64(raw_mime)
        })

      assert {:ok, msg} = SESParser.parse(envelope)
      assert msg.body_text =~ "Plain body"
      assert msg.body_html =~ "<p>HTML body</p>"
    end

    test "leaves body nil when content is missing" do
      envelope =
        notification_envelope(%{
          "mail" => %{
            "commonHeaders" => %{
              "from" => ["alice@example.com"],
              "to" => ["support@example.com"],
              "subject" => "Hi"
            }
          }
        })

      assert {:ok, msg} = SESParser.parse(envelope)
      assert is_nil(msg.body_text)
      assert is_nil(msg.body_html)
      assert msg.from_email == "alice@example.com"
    end

    test "falls back to headers array for threading fields when commonHeaders lacks them" do
      envelope =
        notification_envelope(%{
          "mail" => %{
            "headers" => [
              %{"name" => "Message-ID", "value" => "<fallback@mail.com>"},
              %{"name" => "In-Reply-To", "value" => "<ticket-99@support.example.com>"}
            ],
            "commonHeaders" => %{
              "from" => ["alice@example.com"],
              "to" => ["support@example.com"],
              "subject" => "Fallback"
            }
          }
        })

      assert {:ok, msg} = SESParser.parse(envelope)
      assert msg.message_id == "<fallback@mail.com>"
      assert msg.in_reply_to == "<ticket-99@support.example.com>"
    end
  end

  describe "error handling" do
    test "returns error for unknown envelope types" do
      assert {:error, {:unsupported_sns_envelope, "UnbindConfirmation"}} =
               SESParser.parse(%{"Type" => "UnbindConfirmation"})
    end

    test "returns error when Message field is missing" do
      assert {:error, :missing_message} = SESParser.parse(%{"Type" => "Notification"})
    end

    test "returns error for malformed Message JSON" do
      assert {:error, {:invalid_message_json, _}} =
               SESParser.parse(%{"Type" => "Notification", "Message" => "not json"})
    end

    test "returns error for non-map, non-binary payload" do
      assert {:error, :unsupported_payload} = SESParser.parse(42)
      assert {:error, :unsupported_payload} = SESParser.parse(nil)
    end

    test "accepts raw JSON string payloads" do
      envelope_json =
        Jason.encode!(%{
          "Type" => "Notification",
          "Message" =>
            Jason.encode!(%{
              "mail" => %{
                "commonHeaders" => %{
                  "from" => ["alice@example.com"],
                  "to" => ["support@example.com"],
                  "subject" => "Hi"
                }
              }
            })
        })

      assert {:ok, msg} = SESParser.parse(envelope_json)
      assert msg.from_email == "alice@example.com"
    end
  end

  # ---------- helpers ----------

  defp notification_envelope(ses_message) do
    %{
      "Type" => "Notification",
      "Message" => Jason.encode!(ses_message)
    }
  end
end
