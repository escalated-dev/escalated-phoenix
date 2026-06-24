defmodule Escalated.Controllers.Admin.DataRetentionController do
  @moduledoc """
  Admin data-retention settings plus a read-only purge preview (how many
  records the next `escalated.purge_expired` run would affect). Mirrors
  the Laravel `DataRetentionController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{Attachment, AuditLog, Ticket}
  alias Escalated.Services.SettingsService
  alias Escalated.Support.Retention

  @options %{
    "retention_closed_tickets" => ~w(never 1_year 2_years 3_years 5_years),
    "retention_attachments" => ~w(never 1_year 2_years 3_years 5_years),
    "retention_audit_logs" => ~w(never 90_days 180_days 365_days)
  }

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Settings/DataRetention", %{
      settings: current_settings(),
      purge_preview: purge_preview()
    })
  end

  def update(conn, params) do
    if valid?(params) do
      Enum.each(@options, fn {key, _} ->
        SettingsService.set(key, to_string(params[key]), "retention")
      end)

      SettingsService.set(
        "retention_user_data_gdpr",
        bool_str(params["retention_user_data_gdpr"]),
        "retention"
      )

      conn
      |> put_flash(:info, "Data retention settings updated.")
      |> redirect(to: settings_path())
    else
      conn |> put_status(422) |> json(%{error: "Invalid retention settings."})
    end
  end

  defp valid?(params) do
    Enum.all?(@options, fn {key, allowed} -> to_string(params[key]) in allowed end)
  end

  defp current_settings do
    base =
      Map.new(@options, fn {key, _} -> {key, SettingsService.get_or_default(key, "never")} end)

    gdpr = SettingsService.get_or_default("retention_user_data_gdpr", "0") == "1"
    Map.put(base, "retention_user_data_gdpr", gdpr)
  end

  defp purge_preview do
    %{
      tickets: ticket_candidate_count(),
      attachments: count_older(Attachment, "retention_attachments"),
      audit_logs: count_older(AuditLog, "retention_audit_logs")
    }
  end

  defp ticket_candidate_count do
    case Retention.cutoff_for(SettingsService.get_or_default("retention_closed_tickets", "never")) do
      nil ->
        0

      cutoff ->
        Escalated.repo().aggregate(
          from(t in Ticket, where: t.status == "closed" and t.closed_at < ^cutoff),
          :count
        )
    end
  end

  defp count_older(schema, setting_key) do
    case Retention.cutoff_for(SettingsService.get_or_default(setting_key, "never")) do
      nil ->
        0

      cutoff ->
        Escalated.repo().aggregate(from(r in schema, where: r.inserted_at < ^cutoff), :count)
    end
  end

  defp bool_str(value), do: if(value in [true, "true", "1", 1], do: "1", else: "0")

  defp settings_path do
    "#{Escalated.config(:route_prefix, "/support")}/admin/settings/data-retention"
  end
end
