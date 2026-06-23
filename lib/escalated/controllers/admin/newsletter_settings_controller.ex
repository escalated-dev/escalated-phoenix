defmodule Escalated.Controllers.Admin.NewsletterSettingsController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Controllers.NewsletterHttp, as: NH
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.Newsletter.{Permission, Settings}

  def show(conn, _params) do
    conn = Permission.require_manage!(conn)

    UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Settings", %{
      settings: Settings.show_map(),
      themes: ["default", "branded"]
    })
  end

  def update(conn, params) do
    conn = Permission.require_manage!(conn)

    with {:ok, attrs} <- validate(params) do
      Settings.upsert!(attrs)
      NH.redirect(conn, "#{NH.newsletters_base()}/settings")
    else
      {:error, e} -> NH.bad_request(conn, e)
    end
  end

  defp validate(params) do
    checks = [
      {:default_from, NH.assert_email(param(params, "default_from"), "default_from")},
      {:default_reply_to, NH.assert_email(param(params, "default_reply_to"), "default_reply_to")},
      {:default_theme, NH.required_string(params, "default_theme", 64)},
      {:rate_limit_per_minute, NH.required_integer(params, "rate_limit_per_minute", 1, 10_000)},
      {:batch_size, NH.required_integer(params, "batch_size", 1, 1000)},
      {:tracking_enabled, NH.required_boolean(params, "tracking_enabled")}
    ]

    case NH.collect_errors(Enum.map(checks, fn {_, r} -> r end)) do
      errors when map_size(errors) > 0 -> {:error, errors}
      _ -> {:ok, Enum.into(checks, %{}, fn {k, {:ok, v}} -> {k, v} end)}
    end
  end

  defp param(params, key), do: Map.get(params, key) || Map.get(params, to_string(key))
end
