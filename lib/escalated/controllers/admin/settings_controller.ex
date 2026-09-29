defmodule Escalated.Controllers.Admin.SettingsController do
  @moduledoc """
  Admin controller for viewing and updating Escalated settings.

  Two surfaces:
    * `index` / `update` — the supported general Settings UI, persisted
      through `GeneralSettings` with typed validation.
    * `public_tickets` / `update_public_tickets` — the public-ticket
      guest-policy endpoints. Persist to the `escalated_settings` table
      via `SettingsService` so they survive restarts. Mirrors the
      Symfony, .NET, Go, and Spring ports.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.{GeneralSettings, SettingsService}

  @public_tickets_group "public_tickets"
  @key_mode "guest_policy_mode"
  @key_user_id "guest_policy_user_id"
  @key_signup_url "guest_policy_signup_url_template"
  @valid_modes ~w(unassigned guest_user prompt_signup)

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Settings", %{
      settings: GeneralSettings.all(),
      supported_settings: GeneralSettings.supported_keys(),
      update_url: settings_path()
    })
  end

  def update(conn, params) do
    params = Map.drop(params, ["_csrf_token", "_method"])

    # Preserve the previous nested PUT body for the supported fields.
    params = if Map.keys(params) == ["settings"], do: params["settings"], else: params

    case GeneralSettings.update(params) do
      {:ok, _settings} ->
        conn |> put_flash(:info, "Settings updated.") |> redirect(to: settings_path())

      {:error, errors} ->
        invalid(conn, errors)
    end
  end

  defp invalid(conn, errors) do
    if get_req_header(conn, "x-inertia") == ["true"] and
         Code.ensure_loaded?(Inertia.Controller) do
      # Inertia is optional; assign_errors persists the field errors across
      # the redirect through the host's Inertia.Plug.
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      conn = apply(Inertia.Controller, :assign_errors, [conn, errors])
      redirect(conn, to: settings_path())
    else
      conn |> put_status(422) |> json(%{errors: errors})
    end
  end

  defp settings_path,
    do: "/#{String.trim(Escalated.config(:route_prefix, "/support"), "/")}/admin/settings"

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
