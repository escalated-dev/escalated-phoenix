defmodule Escalated.Services.Email.MessageIdUtilTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.Email.MessageIdUtil

  @domain "support.example.com"
  @secret "test-secret-long-enough-for-hmac"

  describe "build_message_id/3" do
    test "initial ticket form without reply id" do
      assert MessageIdUtil.build_message_id(42, nil, @domain) ==
               "<ticket-42@support.example.com>"
    end

    test "reply form includes -reply-{id}" do
      assert MessageIdUtil.build_message_id(42, 7, @domain) ==
               "<ticket-42-reply-7@support.example.com>"
    end
  end

  describe "parse_ticket_id_from_message_id/1" do
    test "round-trips a built initial id" do
      id = MessageIdUtil.build_message_id(42, nil, @domain)
      assert MessageIdUtil.parse_ticket_id_from_message_id(id) == 42
    end

    test "round-trips a built reply id" do
      id = MessageIdUtil.build_message_id(42, 7, @domain)
      assert MessageIdUtil.parse_ticket_id_from_message_id(id) == 42
    end

    test "accepts value without angle brackets" do
      assert MessageIdUtil.parse_ticket_id_from_message_id("ticket-99@example.com") == 99
    end

    test "returns nil for nil" do
      assert MessageIdUtil.parse_ticket_id_from_message_id(nil) == nil
    end

    test "returns nil for empty string" do
      assert MessageIdUtil.parse_ticket_id_from_message_id("") == nil
    end

    test "returns nil for unrelated input" do
      assert MessageIdUtil.parse_ticket_id_from_message_id("<random@mail.com>") == nil
    end

    test "returns nil for non-numeric ticket id" do
      assert MessageIdUtil.parse_ticket_id_from_message_id("ticket-abc@example.com") == nil
    end
  end

  describe "build_reply_to/3" do
    test "is stable for same inputs" do
      first = MessageIdUtil.build_reply_to(42, @secret, @domain)
      again = MessageIdUtil.build_reply_to(42, @secret, @domain)
      assert first == again
      assert Regex.match?(~r/^reply\+42\.[a-f0-9]{8}@support\.example\.com$/, first)
    end

    test "different tickets produce different signatures" do
      a = MessageIdUtil.build_reply_to(42, @secret, @domain)
      b = MessageIdUtil.build_reply_to(43, @secret, @domain)
      assert String.split(a, "@") != String.split(b, "@")
    end
  end

  describe "verify_reply_to/2" do
    test "round-trips a built address" do
      address = MessageIdUtil.build_reply_to(42, @secret, @domain)
      assert MessageIdUtil.verify_reply_to(address, @secret) == 42
    end

    test "accepts the local part only" do
      address = MessageIdUtil.build_reply_to(42, @secret, @domain)
      [local, _] = String.split(address, "@", parts: 2)
      assert MessageIdUtil.verify_reply_to(local, @secret) == 42
    end

    test "rejects a tampered signature" do
      address = MessageIdUtil.build_reply_to(42, @secret, @domain)
      # Flip the last char of the local part.
      [local, rest] = String.split(address, "@", parts: 2)
      last = String.last(local)
      flipped = if last == "0", do: "1", else: "0"
      tampered = String.slice(local, 0..-2//1) <> flipped <> "@" <> rest
      assert MessageIdUtil.verify_reply_to(tampered, @secret) == nil
    end

    test "rejects a wrong secret" do
      address = MessageIdUtil.build_reply_to(42, @secret, @domain)
      assert MessageIdUtil.verify_reply_to(address, "different-secret") == nil
    end

    test "rejects malformed input" do
      assert MessageIdUtil.verify_reply_to(nil, @secret) == nil
      assert MessageIdUtil.verify_reply_to("", @secret) == nil
      assert MessageIdUtil.verify_reply_to("alice@example.com", @secret) == nil
      assert MessageIdUtil.verify_reply_to("reply@example.com", @secret) == nil
      assert MessageIdUtil.verify_reply_to("reply+abc.deadbeef@example.com", @secret) == nil
    end

    test "is case-insensitive on hex signature" do
      address = MessageIdUtil.build_reply_to(42, @secret, @domain)
      assert MessageIdUtil.verify_reply_to(String.upcase(address), @secret) == 42
    end
  end
end
