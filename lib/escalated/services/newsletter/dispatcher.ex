defmodule Escalated.Services.Newsletter.Dispatcher do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.Contact
  alias Escalated.Schemas.Newsletter.{Newsletter, NewsletterDelivery, NewsletterTemplate}
  alias Escalated.Services.Newsletter.{RateLimit, Renderer}

  @backoff_minutes [1, 5, 30]
  @terminal_statuses ~w(sent bounced complained failed)

  def dispatch_batch do
    if newsletters_enabled?() do
      reclaim_stuck_rows()
      send_batch()
      finalize_completed_newsletters()
      check_auto_pause()
    end

    :ok
  end

  defp newsletters_enabled? do
    Application.get_env(:escalated, :enable_newsletters, false) in [true, "true", 1, "1"]
  end

  defp reclaim_stuck_rows do
    minutes = config_int(:newsletter_claim_timeout_minutes, 10)
    cutoff = DateTime.utc_now() |> DateTime.add(-minutes * 60, :second) |> DateTime.truncate(:second)
    repo = Escalated.repo()

    from(d in NewsletterDelivery,
      where: d.status == "queued" and not is_nil(d.claimed_at) and d.claimed_at < ^cutoff
    )
    |> repo.update_all(set: [status: "pending", claimed_at: nil])
  end

  defp send_batch do
    batch_size = config_int(:newsletter_batch_size, 50)
    rate_limit = config_int(:newsletter_rate_limit_per_minute, 60)
    allowance = max(0, rate_limit - RateLimit.sent_this_minute())

    if allowance > 0 do
      claim_count = min(batch_size, allowance)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      claimed =
        Escalated.repo().transaction(fn repo ->
          pending =
            from(d in NewsletterDelivery,
              where:
                d.status == "pending" and
                  (is_nil(d.next_attempt_at) or d.next_attempt_at <= ^now),
              order_by: [asc: d.id],
              limit: ^claim_count
            )
            |> repo.all()

          ids = Enum.map(pending, & &1.id)

          if ids != [] do
            from(d in NewsletterDelivery, where: d.id in ^ids)
            |> repo.update_all(set: [status: "queued", claimed_at: now])
          end

          pending
        end)
        |> case do
          {:ok, rows} -> rows
          _ -> []
        end

      if claimed != [] do
        RateLimit.increment(length(claimed))
        Enum.each(claimed, &dispatch_one/1)
      end
    end
  end

  defp dispatch_one(delivery) do
    repo = Escalated.repo()

    full =
      repo.one(
        from(d in NewsletterDelivery,
          where: d.id == ^delivery.id,
          preload: []
        )
      )

    newsletter = repo.get(Newsletter, full.newsletter_id)
    contact = repo.get(Contact, full.contact_id)
    template = if newsletter.template_id, do: repo.get(NewsletterTemplate, newsletter.template_id)

    try do
      html = Renderer.render(full, newsletter, contact, template)
      send_mail!(full, newsletter, html)

      repo.update_all(
        from(d in NewsletterDelivery, where: d.id == ^full.id),
        set: [status: "sent", sent_at: utc_now(), claimed_at: nil, next_attempt_at: nil]
      )

      from(n in Newsletter, where: n.id == ^newsletter.id)
      |> repo.update_all(inc: [summary_sent: 1])
    rescue
      error ->
        attempts = full.attempt_count + 1
        reason = Exception.message(error)

        if attempts >= 3 do
          repo.update_all(
            from(d in NewsletterDelivery, where: d.id == ^full.id),
            set: [
              status: "failed",
              failure_reason: reason,
              attempt_count: attempts,
              claimed_at: nil,
              next_attempt_at: nil
            ]
          )
        else
          backoff = Enum.at(@backoff_minutes, attempts - 1, 30)

          repo.update_all(
            from(d in NewsletterDelivery, where: d.id == ^full.id),
            set: [
              status: "pending",
              attempt_count: attempts,
              claimed_at: nil,
              next_attempt_at: DateTime.add(utc_now(), backoff * 60, :second)
            ]
          )
        end
    end
  end

  defp send_mail!(delivery, newsletter, html) do
    mailer = Application.get_env(:escalated, :newsletter_mailer)

    unless is_function(mailer, 1) do
      raise "Mailer not configured — set config :escalated, :newsletter_mailer to enable sending"
    end

    unsub = Renderer.unsubscribe_url(delivery)
    host = newsletter_from_host()

    mailer.(%{
      to: delivery.email_at_send,
      from: format_from(newsletter),
      reply_to: newsletter.reply_to,
      subject: newsletter.subject,
      html: html,
      headers: %{
        "List-Unsubscribe" => "<#{unsub}>",
        "List-Unsubscribe-Post" => "List-Unsubscribe=One-Click",
        "X-Escalated-Newsletter-Id" => Integer.to_string(newsletter.id),
        "Message-ID" => "<n-#{newsletter.id}-#{delivery.tracking_token}@#{host}>"
      }
    })
  end

  defp format_from(%{from_name: name, from_email: email}) when is_binary(name) and name != "" do
    "\"#{name}\" <#{email}>"
  end

  defp format_from(%{from_email: email}), do: email

  defp newsletter_from_host do
    Application.get_env(:escalated, :app_url, "http://localhost")
    |> URI.parse()
    |> Map.get(:host, "localhost")
  end

  defp finalize_completed_newsletters do
    repo = Escalated.repo()
    now = utc_now()

    sending =
      from(n in Newsletter, where: n.status == "sending", select: n.id)
      |> repo.all()

    for newsletter_id <- sending do
      remaining =
        from(d in NewsletterDelivery,
          where:
            d.newsletter_id == ^newsletter_id and d.status in ["pending", "queued"],
          select: count(d.id)
        )
        |> repo.one()

      if remaining == 0 do
        sent_at =
          case repo.one(from(n in Newsletter, where: n.id == ^newsletter_id, select: n.sent_at)) do
            nil -> now
            existing -> existing
          end

        from(n in Newsletter, where: n.id == ^newsletter_id)
        |> repo.update_all(set: [status: "sent", sent_at: sent_at])
      end
    end
  end

  defp check_auto_pause do
    threshold = config_int(:newsletter_auto_pause_threshold, 100)
    rate = config_float(:newsletter_auto_pause_bounce_rate, 0.05)
    repo = Escalated.repo()

    sending_ids =
      from(n in Newsletter, where: n.status == "sending", select: n.id)
      |> repo.all()

    for newsletter_id <- sending_ids do
      sample =
        from(d in NewsletterDelivery,
          where: d.newsletter_id == ^newsletter_id and d.status in ^@terminal_statuses,
          order_by: [asc: d.id],
          limit: ^threshold,
          select: d.status
        )
        |> repo.all()

      if length(sample) >= threshold do
        bounced = Enum.count(sample, &(&1 == "bounced"))

        if bounced / threshold >= rate do
          from(n in Newsletter, where: n.id == ^newsletter_id)
          |> repo.update_all(set: [status: "paused"])
        end
      end
    end
  end

  defp utc_now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp config_int(key, default) do
    case Application.get_env(:escalated, key, default) do
      n when is_integer(n) -> n
      n when is_binary(n) -> String.to_integer(n)
      _ -> default
    end
  end

  defp config_float(key, default) do
    case Application.get_env(:escalated, key, default) do
      n when is_float(n) -> n
      n when is_integer(n) -> n * 1.0
      n when is_binary(n) -> String.to_float(n)
      _ -> default
    end
  end
end
