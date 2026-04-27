defmodule Escalated.Services.Email.Inbound.RouterTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.Email.Inbound.Router
  alias Escalated.Services.Email.MessageIdUtil

  @domain "support.example.com"
  @secret "test-secret-for-hmac"

  # Minimal fake "ticket" struct for test assertions.
  defmodule FakeTicket do
    defstruct [:id, :reference]
  end

  defp lookup(opts \\ []) do
    by_id = Keyword.get(opts, :by_id, %{})
    by_ref = Keyword.get(opts, :by_ref, %{})

    %{
      get_ticket_by_id: fn id -> Map.get(by_id, id) end,
      get_ticket_by_reference: fn ref -> Map.get(by_ref, ref) end
    }
  end

  defp message(overrides \\ []) do
    defaults = %{
      from_email: "customer@example.com",
      to_email: "support@example.com",
      subject: "hello"
    }

    Enum.into(overrides, defaults)
  end

  describe "resolve_ticket/3" do
    test "matches canonical In-Reply-To Message-ID" do
      ticket = %FakeTicket{id: 42}

      m = message(in_reply_to: "<ticket-42@support.example.com>")

      assert Router.resolve_ticket(m, lookup(by_id: %{42 => ticket})) == ticket
    end

    test "matches canonical References header" do
      ticket = %FakeTicket{id: 42}

      m = message(references: "<unrelated@mail.com> <ticket-42@support.example.com>")

      assert Router.resolve_ticket(m, lookup(by_id: %{42 => ticket})) == ticket
    end

    test "verifies signed Reply-To when inbound_secret is set" do
      ticket = %FakeTicket{id: 42}

      to = MessageIdUtil.build_reply_to(42, @secret, @domain)
      m = message(to_email: to)

      result =
        Router.resolve_ticket(m, lookup(by_id: %{42 => ticket}), %{inbound_secret: })

      assert result == ticket
    end

    test "rejects forged Reply-To signature" do
      ticket = %FakeTicket{id: 42}

      forged = MessageIdUtil.build_reply_to(42, "wrong-secret", @domain)
      m = message(to_email: forged)

      result =
        Router.resolve_ticket(m, lookup(by_id: %{42 => ticket}), %{inbound_secret: "real-secret"})

      assert result == nil
    end

    test "ignores signed Reply-To when secret is blank" do
      ticket = %FakeTicket{id: 42}

      to = MessageIdUtil.build_reply_to(42, @secret, @domain)
      m = message(to_email: to)

      # No inbound_secret in options — branch skipped.
      assert Router.resolve_ticket(m, lookup(by_id: %{42 => ticket})) == nil
    end

    test "matches subject-line reference tag" do
      ticket = %FakeTicket{id: 99, reference: "ESC-00099"}

      m = message(subject: "RE: [ESC-00099] help")

      assert Router.resolve_ticket(m, lookup(by_ref: %{"ESC-00099" => ticket})) == ticket
    end

    test "returns nil when nothing matches" do
      m = message(subject: "No match here")

      assert Router.resolve_ticket(m, lookup()) == nil
    end

    test "accepts string keys on message map (for webhook payload pass-through)" do
      ticket = %FakeTicket{id: 42}

      m = %{
        "from_email" => "customer@example.com",
        "to_email" => "support@example.com",
        "subject" => "hi",
        "in_reply_to" => "<ticket-42@support.example.com>"
      }

      assert Router.resolve_ticket(m, lookup(by_id: %{42 => ticket})) == ticket
    end

    test "custom subject pattern override" do
      ticket = %FakeTicket{id: 7, reference: "SUPPORT-007"}

      m = message(subject: "Re: {SUPPORT-007} ping")

      opts = %{subject_pattern: ~r/\{([A-Z]+-[0-9]+)\}/}
      assert Router.resolve_ticket(m, lookup(by_ref: %{"SUPPORT-007" => ticket}), opts) == ticket
    end
  end

  describe "candidate_header_message_ids/1" do
    test "in_reply_to first, then references" do
      m = message(in_reply_to: "<primary@mail>", references: "<a@mail> <b@mail>")

      assert Router.candidate_header_message_ids(m) == [
               "<primary@mail>",
               "<a@mail>",
               "<b@mail>"
             ]
    end

    test "empty headers yields empty list" do
      assert Router.candidate_header_message_ids(message()) == []
    end
  end

  describe "Message.body/1" do
    alias Escalated.Services.Email.Inbound.Message

    test "prefers text body over html" do
      m = %Message{
        from_email: "a@b",
        to_email: "c@d",
        subject: "hi",
        body_text: "plain",
        body_html: "<p>html</p>"
      }

      assert Message.body(m) == "plain"
    end

    test "falls back to html when text is empty" do
      m = %Message{
        from_email: "a@b",
        to_email: "c@d",
        subject: "hi",
        body_text: "",
        body_html: "<p>html</p>"
      }

      assert Message.body(m) == "<p>html</p>"
    end

    test "returns empty string when neither is present" do
      m = %Message{from_email: "a@b", to_email: "c@d", subject: "hi"}

      assert Message.body(m) == ""
    end
  end
end
