defmodule Escalated.Services.Newsletter.ContactSegmentResolverTest do
  use Escalated.NewsletterCase, async: false

  alias Escalated.Schemas.Newsletter.NewsletterListMember
  alias Escalated.Services.Newsletter.ContactSegmentResolver

  test "resolve_sendable skips opted-out contacts", %{repo: repo} do
    list = insert_list!(repo)
    in_contact = insert_contact!(repo, %{email: "in@example.com"})
    out_contact = insert_contact!(repo, %{email: "out@example.com", marketing_opt_out_at: DateTime.utc_now()})

    for c <- [in_contact, out_contact] do
      repo.insert!(NewsletterListMember.changeset(%NewsletterListMember{}, %{list_id: list.id, contact_id: c.id}))
    end

    assert ContactSegmentResolver.resolve_sendable(list) == [in_contact.id]
  end

  test "countMatches ignores unknown filter fields safely", %{repo: repo} do
    insert_contact!(repo, %{email: "a@example.com", name: "Alice"})
    filter = %{"rules" => [%{"field" => "DROP TABLE", "op" => "=", "value" => "x"}]}
    assert ContactSegmentResolver.count_matches(filter) >= 1
  end
end
