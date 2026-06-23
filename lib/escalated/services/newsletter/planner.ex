defmodule Escalated.Services.Newsletter.Planner do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.Contact
  alias Escalated.Schemas.Newsletter.{Newsletter, NewsletterDelivery, NewsletterList}
  alias Escalated.Services.Newsletter.{BounceSuppressionStore, ContactSegmentResolver}

  def plan(%Newsletter{} = newsletter) do
    repo = Escalated.repo()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    repo.update_all(from(n in Newsletter, where: n.id == ^newsletter.id),
      set: [status: "sending"]
    )

    list =
      repo.one(
        from(l in NewsletterList,
          join: n in Newsletter,
          on: n.target_list_id == l.id,
          where: n.id == ^newsletter.id,
          select: l
        )
      )

    if is_nil(list) do
      repo.update_all(
        from(n in Newsletter, where: n.id == ^newsletter.id),
        set: [summary_total: 0]
      )

      :ok
    else
      contact_ids = ContactSegmentResolver.resolve_sendable(list)

      if contact_ids == [] do
        repo.update_all(
          from(n in Newsletter, where: n.id == ^newsletter.id),
          set: [summary_total: 0]
        )
      else
        contacts =
          from(c in Contact, where: c.id in ^contact_ids, select: %{id: c.id, email: c.email})
          |> repo.all()

        sendable =
          contacts
          |> Enum.map(& &1.email)
          |> BounceSuppressionStore.filter_sendable()
          |> MapSet.new(&String.downcase/1)

        rows =
          Enum.flat_map(contacts, fn contact ->
            if String.downcase(contact.email) in sendable do
              [
                %{
                  newsletter_id: newsletter.id,
                  contact_id: contact.id,
                  email_at_send: contact.email,
                  status: "pending",
                  tracking_token: tracking_token(),
                  attempt_count: 0,
                  is_test: false,
                  created_at: now
                }
              ]
            else
              []
            end
          end)

        Enum.chunk_every(rows, 500)
        |> Enum.each(fn chunk ->
          repo.insert_all(NewsletterDelivery, chunk)
        end)

        repo.update_all(
          from(n in Newsletter, where: n.id == ^newsletter.id),
          set: [summary_total: length(rows)]
        )
      end

      :ok
    end
  end

  defp tracking_token do
    20 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
