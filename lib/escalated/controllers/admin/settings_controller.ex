defmodule Escalated.Controllers.Admin.SettingsController do
  @moduledoc """
  Admin controller for viewing and updating Escalated settings.

  Two surfaces:
    * `index` / `update` — the generic Settings UI page. Writes go to
      `Application.put_env` for runtime-applied config.
    * `public_tickets` / `update_public_tickets` — the public-ticket
      guest-policy endpoints. Persist to the `escalated_settings` table
      via `SettingsService` so they survive restarts. Mirrors the
      Symfony, .NET, Go, and Spring ports.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.SettingsService

  @public_tickets_group "public_tickets"
  @key_mode "guest_policy_mode"
  @key_user_id "guest_policy_user_id"
  @key_signup_url "guest_policy_signup_url_template"
  @valid_modes ~w(unassigned guest_user prompt_signup)

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
        notification_channels: config.notification_channels,
        knowledge_base_enabled: config.knowledge_base_enabled,
        knowledge_base_public: config.knowledge_base_public,
        knowledge_base_feedback_enabled: config.knowledge_base_feedback_enabled
      }
    })
  end

  def update(conn, %{"settings" => settings_params}) do
    # Runtime settings updates are applied to the application environment.
    # Only a subset of settings can be changed at runtime.
    runtime_keys = ~w(default_priority allow_customer_close auto_close_resolved_after_days max_attachments max_attachment_size_kb knowledge_base_enabled knowledge_base_public knowledge_base_feedback_enabled)a

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

  @doc """
  GET /admin/settings/public-tickets — returns the three guest-policy
  fields as JSON. Missing keys fall back to the shipped defaults.
  """
  def public_tickets(conn, _params) do
    json(conn, load_public_tickets_settings())
  end

  @doc """
  PUT /admin/settings/public-tickets — validates + persists. Unknown
  mode values coerce to "unassigned"; mode-specific fields are cleared
  on switch so stale values don't leak back into behavior.
  """
  def update_public_tickets(conn, params) do
    mode =
      case params["guest_policy_mode"] do
        m when m in @valid_modes -> m
        _ -> "unassigned"
      end

    SettingsService.set(@key_mode, mode, @public_tickets_group)

    user_id =
      if mode == "guest_user" do
        parse_positive_int(params["guest_policy_user_id"])
      else
        nil
      end

    SettingsService.set(
      @key_user_id,
      if(is_nil(user_id), do: "", else: Integer.to_string(user_id)),
      @public_tickets_group
    )

    template =
      if mode == "prompt_signup" do
        raw = to_string(params["guest_policy_signup_url_template"] || "") |> String.trim()
        if String.length(raw) > 500, do: String.slice(raw, 0, 500), else: raw
      else
        ""
      end

    SettingsService.set(@key_signup_url, template, @public_tickets_group)

    json(conn, load_public_tickets_settings())
  end

  defp load_public_tickets_settings do
    mode = SettingsService.get_or_default(@key_mode, "unassigned")
    user_id_raw = SettingsService.get_or_default(@key_user_id, "")
    template = SettingsService.get_or_default(@key_signup_url, "")

    %{
      "guest_policy_mode" => mode,
      "guest_policy_user_id" => parse_positive_int(user_id_raw),
      "guest_policy_signup_url_template" => template
    }
  end

  @doc false
  @spec parse_positive_int(any()) :: pos_integer() | nil
  def parse_positive_int(nil), do: nil
  def parse_positive_int(""), do: nil

  def parse_positive_int(val) when is_integer(val) do
    if val > 0, do: val, else: nil
  end

  def parse_positive_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  def parse_positive_int(_), do: nil
end
