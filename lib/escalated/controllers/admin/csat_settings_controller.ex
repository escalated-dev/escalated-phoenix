defmodule Escalated.Controllers.Admin.CsatSettingsController do
  @moduledoc """
  Admin CSAT settings (question text, scale, delivery trigger, delay).
  Persisted in the key/value settings store. Mirrors the Laravel
  `CsatSettingsController`.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Controllers.FormResponse
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
    case validate(params) do
      {:ok, values} ->
        Enum.each(values, fn {key, value} -> SettingsService.set(key, value, "csat") end)

        conn
        |> put_flash(:info, "CSAT settings updated.")
        |> redirect(to: settings_path())

      {:error, errors} ->
        FormResponse.invalid(conn, errors, settings_path())
    end
  end

  defp validate(params) do
    question = params["csat_question_text"]
    delay = parse_int(params["csat_delay_hours"])

    errors =
      []
      |> check(
        is_binary(question) and String.trim(question) != "" and String.length(question) <= 500,
        "csat_question_text",
        "The question text is required and may not be longer than 500 characters."
      )
      |> check(params["csat_scale"] in ~w(1-3 1-5), "csat_scale", "The scale must be 1-3 or 1-5.")
      |> check(
        params["csat_delivery_trigger"] in ~w(on_resolve delayed manual),
        "csat_delivery_trigger",
        "The delivery trigger must be on_resolve, delayed or manual."
      )
      |> check(
        is_integer(delay) and delay >= 0 and delay <= 168,
        "csat_delay_hours",
        "The delay must be a whole number of hours between 0 and 168."
      )

    if errors == [] do
      {:ok,
       %{
         "csat_question_text" => question,
         "csat_scale" => params["csat_scale"],
         "csat_delivery_trigger" => params["csat_delivery_trigger"],
         "csat_delay_hours" => Integer.to_string(delay)
       }}
    else
      {:error, Map.new(errors)}
    end
  end

  defp check(errors, true, _field, _message), do: errors
  defp check(errors, _, field, message), do: [{field, [message]} | errors]

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp current_settings do
    @defaults
    |> Map.new(fn {key, default} -> {key, SettingsService.get_or_default(key, default)} end)
    |> Map.update!("csat_delay_hours", &(parse_int(&1) || 0))
  end

  defp settings_path do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/settings/csat"
  end
end
