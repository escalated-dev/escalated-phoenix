defmodule Escalated.Controllers.Admin.WebhookController do
  @moduledoc """
  Admin CRUD over outbound webhook subscriptions plus the per-webhook delivery
  log and a manual delivery retry.

  Mirrors the Laravel `Escalated\\Laravel\\Http\\Controllers\\Admin\\WebhookController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.{Paginator, UIRenderer}
  alias Escalated.Schemas.{Webhook, WebhookDelivery}
  alias Escalated.Services.WebhookDispatcher
  alias Escalated.Webhooks

  # The canonical names this package emits (decisions/2026-10-21-event-vocabulary.md).
  # Legacy names are still honoured on stored webhooks but never offered.
  @available_events Escalated.Events.emitted()

  def index(conn, _params) do
    repo = Escalated.repo()

    # The page reads each webhook's latest delivery from `deliveries[0]`.
    webhooks =
      Enum.map(Webhooks.list_with_delivery_stats(repo), fn webhook ->
        recent = repo |> Webhooks.list_deliveries(webhook.id, 5) |> Enum.map(&delivery_json/1)
        Map.put(webhook, :deliveries, recent)
      end)

    UIRenderer.render_page(conn, "Escalated/Admin/Webhooks/Index", %{
      webhooks: webhooks,
      available_events: @available_events
    })
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Webhooks/Form", %{
      webhook: nil,
      availableEvents: @available_events
    })
  end

  def edit(conn, %{"id" => id}) do
    case Webhooks.get(Escalated.repo(), id) do
      nil ->
        not_found(conn, "Webhook not found")

      %Webhook{} = webhook ->
        UIRenderer.render_page(conn, "Escalated/Admin/Webhooks/Form", %{
          webhook: Webhook.to_json(webhook),
          availableEvents: @available_events
        })
    end
  end

  def create(conn, %{"webhook" => params}), do: do_create(conn, params)
  def create(conn, params), do: do_create(conn, params)

  defp do_create(conn, params) do
    case Webhooks.create(Escalated.repo(), params) do
      {:ok, _webhook} ->
        conn |> put_flash(:info, "Webhook created.") |> redirect(to: admin_webhooks_path())

      {:error, changeset} ->
        FormResponse.invalid(conn, changeset, admin_webhooks_path() <> "/create")
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
        case Webhooks.update(repo, webhook, secret_params(params)) do
          {:ok, _} ->
            conn |> put_flash(:info, "Webhook updated.") |> redirect(to: admin_webhooks_path())

          {:error, cs} ->
            FormResponse.invalid(conn, cs, "#{admin_webhooks_path()}/#{id}/edit")
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
  def deliveries(conn, %{"id" => id} = params) do
    repo = Escalated.repo()

    case Webhooks.get(repo, id) do
      nil ->
        not_found(conn, "Webhook not found")

      %Webhook{} = webhook ->
        query = WebhookDelivery.for_webhook(webhook.id)
        path = "#{admin_webhooks_path()}/#{webhook.id}/deliveries"

        UIRenderer.render_page(conn, "Escalated/Admin/Webhooks/DeliveryLog", %{
          webhook: Webhook.to_json(webhook),
          deliveries:
            Paginator.paginate_query(
              query,
              Escalated.Tenancy.scoped_repo(repo),
              params,
              path,
              &delivery_json/1
            )
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

  # The form never receives the stored secret, so a blank or missing one means
  # "leave it as it is"; `clear_secret: true` removes it; anything else
  # replaces it (escalated-laravel's `WebhookController::update`).
  defp secret_params(params) do
    {secret, params} = Map.pop(params, "secret")
    {clear, params} = Map.pop(params, "clear_secret")

    cond do
      clear in [true, "true", "1", 1, "on"] -> Map.put(params, "secret", nil)
      is_binary(secret) and String.trim(secret) != "" -> Map.put(params, "secret", secret)
      true -> params
    end
  end

  defp delivery_json(delivery) do
    delivery
    |> WebhookDelivery.to_json()
    |> Map.put(:created_at, delivery.inserted_at && DateTime.to_iso8601(delivery.inserted_at))
  end

  defp not_found(conn, message) do
    conn |> put_status(404) |> Phoenix.Controller.json(%{error: message})
  end

  defp admin_webhooks_path do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/webhooks"
  end
end
