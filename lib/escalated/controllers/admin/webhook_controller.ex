defmodule Escalated.Controllers.Admin.WebhookController do
  @moduledoc """
  Admin CRUD over outbound webhook subscriptions plus the per-webhook delivery
  log and a manual delivery retry.

  Mirrors the Laravel `Escalated\\Laravel\\Http\\Controllers\\Admin\\WebhookController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{Webhook, WebhookDelivery}
  alias Escalated.Services.WebhookDispatcher
  alias Escalated.Webhooks

  @available_events [
    "ticket.created",
    "ticket.updated",
    "ticket.status_changed",
    "ticket.resolved",
    "ticket.closed",
    "ticket.reopened",
    "ticket.assigned",
    "ticket.unassigned",
    "ticket.escalated",
    "ticket.priority_changed",
    "ticket.department_changed",
    "reply.created",
    "note.created",
    "sla.breached",
    "sla.warning",
    "ticket.tag_added",
    "ticket.tag_removed"
  ]

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Webhooks/Index", %{
      webhooks: Webhooks.list_with_delivery_stats(Escalated.repo()),
      available_events: @available_events
    })
  end

  def create(conn, %{"webhook" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    case Webhooks.create(Escalated.repo(), params) do
      {:ok, _webhook} ->
        conn |> put_flash(:info, "Webhook created.") |> redirect(to: admin_webhooks_path())

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id, "webhook" => params}), do: do_update(conn, id, params)
  def update(conn, %{"id" => id} = params), do: do_update(conn, id, Map.delete(params, "id"))

  defp do_update(conn, id, params) do
    repo = Escalated.repo()

    case Webhooks.get(repo, id) do
      nil ->
        not_found(conn, "Webhook not found")

      %Webhook{} = webhook ->
        case Webhooks.update(repo, webhook, params) do
          {:ok, _} ->
            conn |> put_flash(:info, "Webhook updated.") |> redirect(to: admin_webhooks_path())

          {:error, cs} ->
            conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(cs)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case Webhooks.get(repo, id) do
      nil ->
        not_found(conn, "Webhook not found")

      %Webhook{} = webhook ->
        Webhooks.delete(repo, webhook)
        conn |> put_flash(:info, "Webhook deleted.") |> redirect(to: admin_webhooks_path())
    end
  end

  @doc "Delivery log for a single webhook."
  def deliveries(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case Webhooks.get(repo, id) do
      nil ->
        not_found(conn, "Webhook not found")

      %Webhook{} = webhook ->
        deliveries = Webhooks.list_deliveries(repo, webhook.id)

        UIRenderer.render_page(conn, "Escalated/Admin/Webhooks/DeliveryLog", %{
          webhook: Webhook.to_json(webhook),
          deliveries: Enum.map(deliveries, &WebhookDelivery.to_json/1)
        })
    end
  end

  @doc "Replay a recorded delivery."
  def retry(conn, %{"id" => id}) do
    case Webhooks.get_delivery(Escalated.repo(), id) do
      nil ->
        not_found(conn, "Delivery not found")

      %WebhookDelivery{} = delivery ->
        WebhookDispatcher.retry_delivery(delivery)

        conn
        |> put_flash(:info, "Webhook delivery retried.")
        |> redirect(to: admin_webhooks_path())
    end
  end

  defp not_found(conn, message) do
    conn |> put_status(404) |> Phoenix.Controller.json(%{error: message})
  end

  defp admin_webhooks_path do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/webhooks"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
