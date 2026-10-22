defmodule Escalated.Controllers.Admin.DataRetentionController do
  @moduledoc """
  Admin data-retention settings plus a read-only purge preview (how many
  records the next `mix escalated.purge_expired` run would delete). Mirrors
  the Laravel `DataRetentionController`.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.{RetentionPurge, SettingsService}

  @options %{
    "retention_closed_tickets" => ~w(never 1_year 2_years 3_years 5_years),
    "retention_attachments" => ~w(never 1_year 2_years 3_years 5_years),
    "retention_audit_logs" => ~w(never 90_days 180_days 365_days)
  }

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Settings/DataRetention", %{
      settings: current_settings(),
      purgePreview: RetentionPurge.preview()
    })
  end

  def update(conn, params) do
    errors =
      for {key, allowed} <- @options, to_string(params[key]) not in allowed, into: %{} do
        {key, ["The selected value is invalid."]}
      end

    gdpr = parse_bool(params["retention_user_data_gdpr"])

    errors =
      if gdpr == :invalid,
        do: Map.put(errors, "retention_user_data_gdpr", ["This field must be true or false."]),
        else: errors

    if errors == %{} do
      Enum.each(@options, fn {key, _} ->
        SettingsService.set(key, to_string(params[key]), "retention")
      end)

      SettingsService.set("retention_user_data_gdpr", if(gdpr, do: "1", else: "0"), "retention")

      conn
      |> put_flash(:info, "Data retention settings updated.")
      |> redirect(to: settings_path())
    else
      FormResponse.invalid(conn, errors, settings_path())
    end
  end

  defp parse_bool(value) when value in [true, "true", "1", 1], do: true
  defp parse_bool(value) when value in [false, "false", "0", 0], do: false
  defp parse_bool(_), do: :invalid

  defp current_settings do
    base =
      Map.new(@options, fn {key, _} -> {key, SettingsService.get_or_default(key, "never")} end)

    gdpr = SettingsService.get_or_default("retention_user_data_gdpr", "0") == "1"
    Map.put(base, "retention_user_data_gdpr", gdpr)
  end

  defp settings_path do
    "#{Escalated.config(:route_prefix, "/support")}/admin/settings/data-retention"
  end
end
