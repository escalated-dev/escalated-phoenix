defmodule Escalated.Controllers.Admin.SettingsController do
  @moduledoc """
  Admin controller for viewing and updating Escalated settings.

  Two surfaces:
    * `index` / `update` — the supported general Settings UI, persisted
      through `GeneralSettings` with typed validation.
    * `public_tickets` / `update_public_tickets` — the public-ticket
      guest-policy page (`Escalated/Admin/Settings/PublicTickets`), with a
      JSON answer kept for JSON clients. Persist to the `escalated_settings`
      table via `SettingsService`. Mirrors Laravel's
      `PublicTicketsSettingsController`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.{GeneralSettings, SettingsService}

  @public_tickets_group "public_tickets"
  @key_mode "guest_policy_mode"
  @key_user_id "guest_policy_user_id"
  @key_signup_url "guest_policy_signup_url_template"
  @valid_modes ~w(unassigned guest_user prompt_signup)

  def index(conn, _params) do
    # `widget_enabled` comes from the host's `:widget_settings` config. It is
    # shown, not supported for saving: the page lists embedding sites only
    # while the widget is on.
    widget_enabled = Map.get(Escalated.config(:widget_settings, %{}), :enabled, true)

    UIRenderer.render_page(conn, "Escalated/Admin/Settings", %{
      settings:
        Map.put(GeneralSettings.all(), "widget_enabled", widget_enabled not in [false, nil]),
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
  GET /admin/settings/public-tickets -- the shared
  `Escalated/Admin/Settings/PublicTickets` page. A JSON client (an `Accept:
  application/json` request that is not an Inertia visit) keeps the plain
  JSON answer it always had. Missing keys fall back to the shipped defaults.
  """
  def public_tickets(conn, _params) do
    if json_client?(conn) do
      json(conn, load_public_tickets_settings())
    else
      settings = load_public_tickets_settings()

      UIRenderer.render_page(conn, "Escalated/Admin/Settings/PublicTickets", %{
        settings: %{
          settings
          | "guest_policy_user_id" =>
              settings["guest_policy_user_id"] &&
                Integer.to_string(settings["guest_policy_user_id"])
        }
      })
    end
  end

  @doc """
  POST or PUT /admin/settings/public-tickets -- validates and persists the
  guest policy (the same keys the widget and guest flow read). Mode-specific
  fields are cleared on switch so stale values don't leak back into behavior.
  An Inertia visit is redirected back with a flash or field errors; a JSON
  client gets the saved settings, or a 422 with the errors.
  """
  def update_public_tickets(conn, params) do
    case validate_public_tickets(params) do
      {:ok, mode, user_id, template} ->
        SettingsService.set(@key_mode, mode, @public_tickets_group)
        SettingsService.set(@key_user_id, user_id, @public_tickets_group)
        SettingsService.set(@key_signup_url, template, @public_tickets_group)

        if json_client?(conn) do
          json(conn, load_public_tickets_settings())
        else
          conn
          |> put_flash(:info, "Guest policy updated.")
          |> redirect(to: public_tickets_path())
        end

      {:error, errors} ->
        FormResponse.invalid(conn, errors, public_tickets_path())
    end
  end

  defp validate_public_tickets(params) do
    mode = params["guest_policy_mode"]
    raw_user_id = params["guest_policy_user_id"]
    user_id = parse_positive_int(raw_user_id)
    template = params["guest_policy_signup_url_template"]

    errors =
      %{}
      |> put_error(
        mode not in @valid_modes,
        "guest_policy_mode",
        "The guest policy must be unassigned, guest_user or prompt_signup."
      )
      |> put_error(
        raw_user_id not in [nil, ""] and is_nil(user_id),
        "guest_policy_user_id",
        "The guest user must be a positive user id."
      )
      |> put_error(
        mode == "guest_user" and is_nil(user_id),
        "guest_policy_user_id",
        "A guest user is required for the guest_user policy."
      )
      |> put_error(
        not (is_nil(template) or (is_binary(template) and String.length(template) <= 500)),
        "guest_policy_signup_url_template",
        "The signup URL template may not be longer than 500 characters."
      )

    if errors == %{} do
      {:ok, mode, if(mode == "guest_user", do: Integer.to_string(user_id), else: ""),
       if(mode == "prompt_signup", do: String.trim(template || ""), else: "")}
    else
      {:error, errors}
    end
  end

  defp put_error(errors, true, field, message), do: Map.put_new(errors, field, [message])
  defp put_error(errors, _, _field, _message), do: errors

  defp json_client?(conn) do
    not FormResponse.inertia?(conn) and
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "json"))
  end

  defp public_tickets_path, do: settings_path() <> "/public-tickets"

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
