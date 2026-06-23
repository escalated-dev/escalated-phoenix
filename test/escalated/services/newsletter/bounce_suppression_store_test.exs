defmodule Escalated.Services.Newsletter.BounceSuppressionStoreTest do
  use Escalated.NewsletterCase, async: false

  alias Escalated.Services.Newsletter.BounceSuppressionStore

  test "marks bounced and complained emails as suppressed", %{repo: _} do
    BounceSuppressionStore.mark_bounced("Bounce@Example.com")
    assert BounceSuppressionStore.is_bounced?("bounce@example.com")
    BounceSuppressionStore.mark_complained("other@example.com")

    assert BounceSuppressionStore.filter_sendable(["other@example.com", "safe@example.com"]) == [
             "safe@example.com"
           ]
  end
end
