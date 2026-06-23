defmodule Escalated.Controllers.Webhooks.NewsletterEspWebhookController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Escalated.Controllers.NewsletterHttp, as: NH
  alias Escalated.Services.Newsletter.Tracker

  def postmark(conn, params) do
    token = NH.token_from_message_id(to_string(params["MessageID"] || ""))

    case params["RecordType"] do
      "Open" ->
        Tracker.record_open(token)

      "Click" ->
        Tracker.record_click(token, to_string(params["OriginalLink"] || ""))

      "Bounce" ->
        Tracker.record_bounce(
          token,
          bounce_type(params["Type"]),
          to_string(params["Description"] || "")
        )

      "SpamComplaint" ->
        Tracker.record_complaint(token)

      _ ->
        :ok
    end

    json(conn, %{ok: true})
  end

  def mailgun(conn, params) do
    event = get_in(params, ["event-data", "event"])
    message_id = get_in(params, ["event-data", "message", "headers", "message-id"]) || ""
    token = NH.token_from_message_id(to_string(message_id))

    case event do
      "opened" ->
        Tracker.record_open(token)

      "clicked" ->
        Tracker.record_click(token, to_string(get_in(params, ["event-data", "url"]) || ""))

      "failed" ->
        severity = get_in(params, ["event-data", "severity"])
        type = if severity == "permanent", do: "hard", else: "soft"
        reason = get_in(params, ["event-data", "delivery-status", "description"]) || ""
        Tracker.record_bounce(token, type, to_string(reason))

      "complained" ->
        Tracker.record_complaint(token)

      _ ->
        :ok
    end

    json(conn, %{ok: true})
  end

  def ses(conn, params) do
    message =
      case params["Message"] do
        msg when is_binary(msg) -> Jason.decode!(msg)
        msg when is_map(msg) -> msg
        _ -> params
      end

    token = NH.token_from_message_id(to_string(get_in(message, ["mail", "messageId"]) || ""))

    case message["eventType"] do
      "Open" ->
        Tracker.record_open(token)

      "Click" ->
        Tracker.record_click(token, to_string(get_in(message, ["click", "link"]) || ""))

      "Bounce" ->
        type =
          if get_in(message, ["bounce", "bounceType"]) == "Permanent", do: "hard", else: "soft"

        Tracker.record_bounce(token, type, get_in(message, ["bounce", "bounceSubType"]))

      "Complaint" ->
        Tracker.record_complaint(token)

      _ ->
        :ok
    end

    json(conn, %{ok: true})
  end

  def sendgrid(conn, params) do
    events = if is_list(params), do: params, else: params["_json"] || []

    for event <- List.wrap(events) do
      token =
        NH.token_from_message_id(to_string(event["smtp-id"] || event["sg_message_id"] || ""))

      case event["event"] do
        "open" ->
          Tracker.record_open(token)

        "click" ->
          Tracker.record_click(token, to_string(event["url"] || ""))

        "bounce" ->
          type = if event["type"] == "blocked", do: "hard", else: "soft"
          Tracker.record_bounce(token, type, event["reason"])

        "dropped" ->
          Tracker.record_bounce(token, "hard", event["reason"])

        "spamreport" ->
          Tracker.record_complaint(token)

        _ ->
          :ok
      end
    end

    json(conn, %{ok: true})
  end

  defp bounce_type(type) do
    if type in ["HardBounce", "BadEmailAddress", "BlockedRecipient"], do: "hard", else: "soft"
  end
end
