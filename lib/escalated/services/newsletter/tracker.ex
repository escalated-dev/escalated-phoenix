defmodule Escalated.Services.Newsletter.Tracker do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.Newsletter.{Newsletter, NewsletterDelivery}
  alias Escalated.Services.Newsletter.BounceSuppressionStore

  @terminal ~w(bounced complained failed)

  def record_open(token) when is_binary(token) do
    with %NewsletterDelivery{} = delivery <- find_by_token(token),
         false <- delivery.status in @terminal,
         true <- is_nil(delivery.opened_at) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      repo = Escalated.repo()

      repo.transaction(fn ->
        from(d in NewsletterDelivery, where: d.id == ^delivery.id)
        |> repo.update_all(set: [opened_at: now])

        from(n in Newsletter, where: n.id == ^delivery.newsletter_id)
        |> repo.update_all(inc: [summary_opened: 1])
      end)
    else
      _ -> :ok
    end

    :ok
  end

  def record_click(token, _url) when is_binary(token) do
    with %NewsletterDelivery{} = delivery <- find_by_token(token),
         false <- delivery.status in @terminal do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      first_click = delivery.clicks_count == 0
      repo = Escalated.repo()

      repo.transaction(fn ->
        from(d in NewsletterDelivery, where: d.id == ^delivery.id)
        |> repo.update_all(set: [clicks_count: delivery.clicks_count + 1, last_clicked_at: now])

        if is_nil(delivery.opened_at) do
          from(d in NewsletterDelivery, where: d.id == ^delivery.id)
          |> repo.update_all(set: [opened_at: now])

          from(n in Newsletter, where: n.id == ^delivery.newsletter_id)
          |> repo.update_all(inc: [summary_opened: 1])
        end

        if first_click do
          from(n in Newsletter, where: n.id == ^delivery.newsletter_id)
          |> repo.update_all(inc: [summary_clicked: 1])
        end
      end)
    else
      _ -> :ok
    end

    :ok
  end

  def record_bounce(token, type, reason \\ nil)
      when is_binary(token) and type in ["hard", "soft", :hard, :soft] do
    type = to_string(type)

    with %NewsletterDelivery{} = delivery <- find_by_token(token),
         true <- type == "hard",
         false <- delivery.status == "bounced" do
      repo = Escalated.repo()

      repo.transaction(fn ->
        from(d in NewsletterDelivery, where: d.id == ^delivery.id)
        |> repo.update_all(set: [status: "bounced", bounce_reason: reason])

        from(n in Newsletter, where: n.id == ^delivery.newsletter_id)
        |> repo.update_all(inc: [summary_bounced: 1])
      end)

      BounceSuppressionStore.mark_bounced(delivery.email_at_send)
    else
      _ -> :ok
    end

    :ok
  end

  def record_complaint(token) when is_binary(token) do
    with %NewsletterDelivery{} = delivery <- find_by_token(token),
         false <- delivery.status == "complained" do
      repo = Escalated.repo()

      repo.transaction(fn ->
        from(d in NewsletterDelivery, where: d.id == ^delivery.id)
        |> repo.update_all(set: [status: "complained"])

        from(n in Newsletter, where: n.id == ^delivery.newsletter_id)
        |> repo.update_all(inc: [summary_complained: 1])
      end)

      BounceSuppressionStore.mark_complained(delivery.email_at_send)
    else
      _ -> :ok
    end

    :ok
  end

  defp find_by_token(token) do
    Escalated.repo().one(from(d in NewsletterDelivery, where: d.tracking_token == ^token))
  end
end
