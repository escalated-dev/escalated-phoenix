defmodule Escalated.Controllers.Admin.EmailSettingsController do
  @moduledoc """
  The support email addresses list and default reply address
  (`Escalated/Admin/Settings/EmailSettings`). Mirrors the Laravel
  `EmailSettingsController`: two keys in the settings store,
  `email_addresses` (a JSON array) and `default_reply_address`.

  These are stored for the panel only. Outbound mail still uses the host's
  mailer configuration and the `email_channels` table is untouched.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.SettingsService

  @group "email"
  @dkim ~w(verified pending failed unknown)
  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  def index(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Settings/EmailSettings", %{
      addresses: addresses(),
      defaultReplyAddress: SettingsService.get_or_default("default_reply_address", "")
    })
  end

  def update(conn, params) do
    case validate(params) do
      {:ok, addresses, reply} ->
        SettingsService.set("email_addresses", Jason.encode!(addresses), @group)
        if reply != :absent, do: SettingsService.set("default_reply_address", reply, @group)

        conn
        |> put_flash(:info, "Email settings updated.")
        |> redirect(to: settings_path())

      {:error, errors} ->
        FormResponse.invalid(conn, errors, settings_path())
    end
  end

  defp validate(params) do
    {addresses, errors} = validate_addresses(params["addresses"])
    {reply, errors} = validate_reply(Map.fetch(params, "default_reply_address"), errors)

    if errors == %{}, do: {:ok, addresses, reply}, else: {:error, errors}
  end

  defp validate_addresses(list) when is_list(list) and list != [] do
    list
    |> Enum.with_index()
    |> Enum.reduce({[], %{}}, fn {entry, i}, {acc, errors} ->
      entry = if is_map(entry), do: entry, else: %{}
      {address, errors} = validate_address(entry, "addresses.#{i}", errors)
      {acc ++ [address], errors}
    end)
  end

  defp validate_addresses(_),
    do: {[], %{"addresses" => ["At least one email address is required."]}}

  defp validate_address(entry, path, errors) do
    email = entry["email"]
    name = entry["display_name"]
    department = entry["department_id"]
    dkim = entry["dkim_status"]

    errors =
      errors
      |> check(valid_email?(email), "#{path}.email", "A valid email address is required.")
      |> check(
        is_nil(name) or (is_binary(name) and String.length(name) <= 255),
        "#{path}.display_name",
        "The display name may not be longer than 255 characters."
      )
      |> check(
        department in [nil, ""] or is_integer(parse_int(department)),
        "#{path}.department_id",
        "The department must be an id."
      )
      |> check(dkim in [nil, "" | @dkim], "#{path}.dkim_status", "The DKIM status is invalid.")

    {%{
       "email" => email,
       "display_name" => if(name in [nil, ""], do: nil, else: name),
       "department_id" => parse_int(department),
       "dkim_status" => if(dkim in [nil, ""], do: "unknown", else: dkim)
     }, errors}
  end

  defp validate_reply(:error, errors), do: {:absent, errors}
  defp validate_reply({:ok, value}, errors) when value in [nil, ""], do: {:absent, errors}

  defp validate_reply({:ok, value}, errors) do
    if valid_email?(value),
      do: {value, errors},
      else:
        {:absent,
         Map.put(errors, "default_reply_address", [
           "The default reply address must be a valid email address."
         ])}
  end

  defp valid_email?(value),
    do: is_binary(value) and String.length(value) <= 255 and Regex.match?(@email, value)

  defp check(errors, true, _field, _message), do: errors
  defp check(errors, _, field, message), do: Map.put(errors, field, [message])

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp addresses do
    case Jason.decode(SettingsService.get_or_default("email_addresses", "[]") || "[]") do
      {:ok, list} when is_list(list) -> Enum.filter(list, &is_map/1)
      _ -> []
    end
  end

  defp settings_path,
    do: "#{Escalated.config(:route_prefix, "/support")}/admin/settings/email"
end
