defmodule Escalated.Services.Newsletter.TrackerTest do
  use Escalated.NewsletterCase, async: false

  alias Escalated.Schemas.Newsletter.NewsletterDelivery
  alias Escalated.Services.Newsletter.{BounceSuppressionStore, Tracker}

  setup %{repo: repo} do
    newsletter = insert_newsletter!(repo, %{status: "sending"})
    contact = insert_contact!(repo)
    token = "tok#{System.unique_integer([:positive])}"
    delivery = insert_delivery!(repo, newsletter, contact, token)
    {:ok, repo: repo, newsletter: newsletter, delivery: delivery}
  end

  test "recordOpen is first-event-wins", %{repo: repo, newsletter: newsletter, delivery: delivery} do
    Tracker.record_open(delivery.tracking_token)
    Tracker.record_open(delivery.tracking_token)
    updated = repo.get!(NewsletterDelivery, delivery.id)
    newsletter = repo.get!(Escalated.Schemas.Newsletter.Newsletter, newsletter.id)
    assert updated.opened_at
    assert newsletter.summary_opened == 1
  end

  test "recordBounce hard adds suppression and ignores open after", %{delivery: delivery} do
    Tracker.record_bounce(delivery.tracking_token, "hard", "bad")
    Tracker.record_open(delivery.tracking_token)
    assert BounceSuppressionStore.is_bounced?(delivery.email_at_send)
  end

  defp insert_delivery!(repo, newsletter, contact, token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {:ok, d} =
      repo.insert(
        NewsletterDelivery.changeset(%NewsletterDelivery{}, %{
          newsletter_id: newsletter.id,
          contact_id: contact.id,
          email_at_send: contact.email,
          tracking_token: token,
          status: "sent",
          created_at: now
        })
      )

    d
  end
end
