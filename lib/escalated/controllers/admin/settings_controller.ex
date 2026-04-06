defmodule Escalated.Controllers.Admin.SettingsController do
  @moduledoc """
  Admin controller for viewing and updating Escalated settings.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Rendering.UIRenderer

  def index(conn, _params) do
    config = Escalated.configuration()

    UIRenderer.render_page(conn, "Escalated/Admin/Settings/Index", %{
      settings: %{
        route_prefix: config.route_prefix,
        table_prefix: config.table_prefix,
        ui_enabled: config.ui_enabled,
        api_enabled: config.api_enabled,
        default_priority: config.default_priority,
        allow_customer_close: config.allow_customer_close,
        auto_close_resolved_after_days: config.auto_close_resolved_after_days,
        max_attachments: config.max_attachments,
        max_attachment_size_kb: config.max_attachment_size_kb,
        sla: config.sla,
        notification_channels: config.notification_channels
      }
    })
  end

  def update(conn, %{"settings" => settings_params}) do
    # Runtime settings updates are applied to the application environment.
    # Only a subset of settings can be changed at runtime.
    runtime_keys = ~w(default_priority allow_customer_close auto_close_resolved_after_days max_attachments max_attachment_size_kb)a

    Enum.each(runtime_keys, fn key ->
      str_key = to_string(key)

      if Map.has_key?(settings_params, str_key) do
        Application.put_env(:escalated, key, settings_params[str_key])
      end
    end)

    conn
    |> put_flash(:info, "Settings updated.")
    |> redirect(to: "#{Escalated.config(:route_prefix, "/support")}/admin/settings")
  end
end
