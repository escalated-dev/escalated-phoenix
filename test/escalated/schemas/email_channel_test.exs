defmodule Escalated.Schemas.EmailChannelTest do
  use ExUnit.Case, async: true
  alias Escalated.Schemas.EmailChannel

  test "changeset validates email format" do
    changeset = EmailChannel.changeset(%EmailChannel{}, %{email_address: "invalid"})
    assert {:error, _} = Ecto.Changeset.apply_action(changeset, :insert)
  end

  test "changeset accepts valid email" do
    changeset = EmailChannel.changeset(%EmailChannel{}, %{email_address: "support@example.com"})
    assert changeset.valid?
  end

  test "formatted_sender with display name" do
    channel = %EmailChannel{email_address: "support@example.com", display_name: "Support Team"}
    assert EmailChannel.formatted_sender(channel) == "Support Team <support@example.com>"
  end

  test "formatted_sender without display name" do
    channel = %EmailChannel{email_address: "support@example.com", display_name: nil}
    assert EmailChannel.formatted_sender(channel) == "support@example.com"
  end
end
