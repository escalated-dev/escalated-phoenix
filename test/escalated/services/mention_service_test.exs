defmodule Escalated.Services.MentionServiceTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.MentionService

  test "extracts single mention" do
    assert MentionService.extract_mentions("Hello @john please review") == ["john"]
  end

  test "extracts multiple mentions" do
    result = MentionService.extract_mentions("@alice and @bob please check")
    assert "alice" in result
    assert "bob" in result
  end

  test "extracts dotted usernames" do
    assert MentionService.extract_mentions("cc @john.doe") == ["john.doe"]
  end

  test "deduplicates mentions" do
    assert MentionService.extract_mentions("@alice said @alice should review") == ["alice"]
  end

  test "returns empty for nil" do
    assert MentionService.extract_mentions(nil) == []
  end

  test "returns empty for no mentions" do
    assert MentionService.extract_mentions("No mentions here") == []
  end

  test "extracts username from email" do
    assert MentionService.extract_username_from_email("john@example.com") == "john"
  end
end
