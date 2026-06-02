defmodule Escalated.Controllers.Public.NewsletterTrackingController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Controllers.NewsletterHttp, as: NH
  alias Escalated.Schemas.Contact
  alias Escalated.Schemas.Newsletter.{Newsletter, NewsletterDelivery, NewsletterTemplate}
  alias Escalated.Services.Newsletter.{Renderer, Tracker}

  @unsub_attempts :escalated_newsletter_unsub_attempts

  def open(conn, %{"token" => token}) do
    clean = token |> String.replace(~r/\.(gif|png|jpg)$/i, "")
    Tracker.record_open(clean)

    conn
    |> put_resp_content_type("image/png")
    |> put_resp_header("cache-control", "private, no-store, max-age=0")
    |> send_resp(200, NH.pixel_png())
  end

  def click(conn, %{"token" => token} = params) do
    case NH.decode_tracked_url(params["u"] || "") do
      {:ok, destination} ->
        Tracker.record_click(token, destination)
        conn |> redirect(external: destination) |> halt()

      :error ->
        conn |> put_status(400) |> text("Bad request") |> halt()
    end
  end

  def unsubscribe_show(conn, %{"token" => token}) do
    delivery = find_delivery(token)
    conn |> put_resp_content_type("text/html") |> send_resp(200, unsubscribe_html(token, delivery, false))
  end

  def unsubscribe_store(conn, %{"token" => token}) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    if too_many_unsubscribes?(ip) do
      conn |> put_status(429) |> text("Too Many Requests") |> halt()
    else
      delivery = find_delivery(token)

      if delivery && delivery.contact_id do
        Escalated.repo().update_all(
          from(c in Contact, where: c.id == ^delivery.contact_id),
          set: [marketing_opt_out_at: DateTime.utc_now() |> DateTime.truncate(:second)]
        )
      end

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, unsubscribe_html(token, delivery, true))
    end
  end

  def view(conn, %{"token" => token}) do
    repo = Escalated.repo()

    delivery = repo.one(from(d in NewsletterDelivery, where: d.tracking_token == ^token))

    html =
      if delivery do
        newsletter = repo.get!(Newsletter, delivery.newsletter_id)
        contact = repo.get!(Contact, delivery.contact_id)
        template = if newsletter.template_id, do: repo.get(NewsletterTemplate, newsletter.template_id)
        Renderer.render(delivery, newsletter, contact, template)
      else
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Email unavailable</title></head><body><p>This email is no longer available.</p></body></html>"
      end

    conn |> put_resp_content_type("text/html") |> send_resp(200, html)
  end

  defp find_delivery(token) do
    Escalated.repo().one(from(d in NewsletterDelivery, where: d.tracking_token == ^token))
  end

  defp too_many_unsubscribes?(ip) do
    :ets.insert_new(@unsub_attempts, {ip, 1, System.monotonic_time(:millisecond) + 60_000})

    case :ets.lookup(@unsub_attempts, ip) do
      [{^ip, count, expires}] ->
        now = System.monotonic_time(:millisecond)

        if now > expires do
          :ets.insert(@unsub_attempts, {ip, 1, now + 60_000})
          false
        else
          :ets.insert(@unsub_attempts, {ip, count + 1, expires})
          count + 1 > 60
        end

      _ ->
        false
    end
  rescue
    _ ->
      :ets.new(@unsub_attempts, [:named_table, :set, :public])
      false
  end

  defp unsubscribe_html(token, delivery, confirmed) do
    email = if delivery, do: delivery.email_at_send, else: nil
    message = if confirmed, do: "You have been unsubscribed.", else: "Confirm that you want to unsubscribe from marketing emails."
    prefix = NH.route_prefix()

    """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><title>Unsubscribe</title></head><body><main><h1>Unsubscribe</h1><p>#{escape(message)}</p><p>#{escape(email || "")}</p><form method="post" action="#{prefix}/escalated/n/u/#{escape(token)}"><button type="submit">Unsubscribe</button></form></main></body></html>
    """
  end

  defp escape(value) when is_binary(value) do
    value
    |> Plug.HTML.html_escape()
    |> IO.iodata_to_binary()
  end

  defp escape(_), do: ""
end
