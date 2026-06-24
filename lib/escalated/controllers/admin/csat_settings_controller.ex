defmodule Escalated.Controllers.Admin.CsatSettingsController do
  @moduledoc """
  Admin CSAT settings (question text, scale, delivery trigger, delay).
  Persisted in the key/value settings store. Mirrors the Laravel
  `CsatSettingsController`.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.SettingsService

  @defaults %{
    "csat_question_text" => "How would you rate your support experience?",
    "csat_scale" => "1-5",
    "csat_delivery_trigger" => "on_resolve",
    "csat_delay_hours" => "0"
  }

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Settings/CsatSettings", %{
      settings: current_settings()
    })
  end

  def update(conn, params) do
    Enum.each(Map.keys(@defaults), fn key ->
      if Map.has_key?(params, key) do
        SettingsService.set(key, to_string(params[key]), "csat")
      end
    end)

    conn
    |> put_flash(:info, "CSAT settings updated.")
    |> redirect(to: settings_path())
  end

  defp current_settings do
    Map.new(@defaults, fn {key, default} ->
      {key, SettingsService.get_or_default(key, default)}
    end)
  end

  defp settings_path do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/settings/csat"
  end
end
