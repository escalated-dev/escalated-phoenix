defmodule Escalated.Services.Newsletter.PlannerTest do
  use Escalated.NewsletterCase, async: false

  import Ecto.Query
  alias Escalated.Schemas.Newsletter.NewsletterDelivery
  alias Escalated.Services.Newsletter.{BounceSuppressionStore, Planner}

  test "creates pending deliveries and skips opted-out + suppressed", %{repo: repo} do
    list = insert_list!(repo)
    ok = insert_contact!(repo, %{email: "ok@example.com"})

    opted =
      insert_contact!(repo, %{email: "opt@example.com", marketing_opt_out_at: DateTime.utc_now()})

    bounced = insert_contact!(repo, %{email: "bad@example.com"})

    for c <- [ok, opted, bounced] do
      repo.insert!(
        Escalated.Schemas.Newsletter.NewsletterListMember.changeset(
          %Escalated.Schemas.Newsletter.NewsletterListMember{},
          %{
            list_id: list.id,
            contact_id: c.id
          }
        )
      )
    end

    BounceSuppressionStore.mark_bounced("bad@example.com")
    newsletter = insert_newsletter!(repo, %{target_list_id: list.id, status: "draft"})
    Planner.plan(newsletter)

    deliveries = repo.all(from(d in NewsletterDelivery, where: d.newsletter_id == ^newsletter.id))
    assert length(deliveries) == 1
    assert hd(deliveries).email_at_send == "ok@example.com"

    newsletter = repo.get!(Escalated.Schemas.Newsletter.Newsletter, newsletter.id)
    assert newsletter.status == "sending"
    assert newsletter.summary_total == 1
  end
end
