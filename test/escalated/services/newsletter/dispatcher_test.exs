defmodule Escalated.Services.Newsletter.DispatcherTest do
  use Escalated.NewsletterCase, async: false

  import Ecto.Query
  alias Escalated.Schemas.Newsletter.{Newsletter, NewsletterDelivery}
  alias Escalated.Services.Newsletter.{Dispatcher, Planner}

  setup %{repo: repo} do
    Escalated.Services.Newsletter.RateLimit.reset()
    sent_counter = :atomics.new(1, [])

    Application.put_env(:escalated, :newsletter_mailer, fn _ ->
      :atomics.add(sent_counter, 1, 1)
      :ok
    end)

    on_exit(fn -> Escalated.Services.Newsletter.RateLimit.reset() end)

    {:ok, repo: repo, sent_counter: sent_counter}
  end

  test "claims pending rows and marks sent", %{repo: repo, sent_counter: sent_counter} do
    newsletter = setup_campaign!(repo, 1)
    Dispatcher.dispatch_batch()
    delivery = repo.one!(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id))
    newsletter = repo.get!(Newsletter, newsletter.id)
    assert delivery.status == "sent"
    assert delivery.sent_at
    assert newsletter.summary_sent == 1
    assert :atomics.get(sent_counter, 1) == 1
  end

  test "respects batch size", %{repo: repo, sent_counter: sent_counter} do
    Application.put_env(:escalated, :newsletter_batch_size, 2)
    newsletter = setup_campaign!(repo, 5)
    Dispatcher.dispatch_batch()
    sent_count = repo.aggregate(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id and d.status == "sent"), :count)
    assert sent_count == 2
    assert :atomics.get(sent_counter, 1) == 2
  end

  test "rate limit across ticks", %{repo: repo} do
    Application.put_env(:escalated, :newsletter_rate_limit_per_minute, 2)
    Application.put_env(:escalated, :newsletter_batch_size, 50)
    newsletter = setup_campaign!(repo, 5)
    Dispatcher.dispatch_batch()
    first = repo.aggregate(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id and d.status == "sent"), :count)
    Dispatcher.dispatch_batch()
    second = repo.aggregate(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id and d.status == "sent"), :count)
    assert first == 2
    assert second == 2
  end

  test "does not claim future next_attempt_at", %{repo: repo} do
    newsletter = setup_campaign!(repo, 1)
    future = DateTime.utc_now() |> DateTime.add(3600, :second)
    repo.update_all(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id), set: [next_attempt_at: future])
    Dispatcher.dispatch_batch()
    delivery = repo.one!(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id))
    assert delivery.status == "pending"
  end

  test "auto-pauses when first-N bounce rate exceeded", %{repo: repo} do
    Application.put_env(:escalated, :newsletter_auto_pause_threshold, 4)
    Application.put_env(:escalated, :newsletter_auto_pause_bounce_rate, 0.05)
    newsletter = insert_newsletter!(repo, %{status: "sending", summary_total: 4})

    for i <- 1..4 do
      contact = insert_contact!(repo, %{email: "u#{i}@example.com"})
      status = if i == 1, do: "bounced", else: "sent"

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      repo.insert!(NewsletterDelivery.changeset(%NewsletterDelivery{}, %{
        newsletter_id: newsletter.id,
        contact_id: contact.id,
        email_at_send: contact.email,
        tracking_token: "tok#{i}#{System.unique_integer()}",
        status: status,
        created_at: now
      }))
    end

    pending_contact = insert_contact!(repo, %{email: "pending@example.com"})
    future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    repo.insert!(NewsletterDelivery.changeset(%NewsletterDelivery{}, %{
      newsletter_id: newsletter.id,
      contact_id: pending_contact.id,
      email_at_send: pending_contact.email,
      tracking_token: "tok-pending#{System.unique_integer()}",
      status: "pending",
      next_attempt_at: future,
      created_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }))

    Dispatcher.dispatch_batch()
    assert repo.get!(Newsletter, newsletter.id).status == "paused"
  end

  test "no-op when newsletters disabled", %{repo: repo} do
    newsletter = setup_campaign!(repo, 1)
    Application.put_env(:escalated, :enable_newsletters, false)

    Dispatcher.dispatch_batch()

    delivery = repo.one!(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id))
    assert delivery.status == "pending"
  end

  defp setup_campaign!(repo, count) do
    list = insert_list!(repo)

    contacts =
      for _ <- 1..count do
        c = insert_contact!(repo)
        repo.insert!(Escalated.Schemas.Newsletter.NewsletterListMember.changeset(%Escalated.Schemas.Newsletter.NewsletterListMember{}, %{list_id: list.id, contact_id: c.id}))
        c
      end

    newsletter = insert_newsletter!(repo, %{target_list_id: list.id, status: "draft"})
    Planner.plan(newsletter)
    newsletter
  end
end
