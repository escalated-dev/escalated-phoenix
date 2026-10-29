defmodule Escalated.Controllers.TwoFactorChallengeController do
  @moduledoc """
  The second step after the host's password login (ADR
  2026-10-29-configurable-access-features): renders the shared
  `Escalated/Auth/TwoFactorChallenge` page and checks a TOTP `code` or a
  `recovery_code`.

  Success renews the session ID, marks the session as passed for this user
  and sign-in (`Escalated.TwoFactorSession`), and returns to the page that
  was asked for. Failure answers a validation error on the field sent. The
  verify route is throttled (`Escalated.Plugs.TwoFactorRateLimit`). Mounted
  only while two-factor is switched on.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  require Logger

  alias Escalated.Controllers.FormResponse
  alias Escalated.Plugs.RequireTwoFactor
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.TwoFactorService
  alias Escalated.TwoFactorSession

  def show(conn, _params) do
    user = conn.assigns[:current_user]

    cond do
      is_nil(user) ->
        unauthenticated(conn)

      is_nil(TwoFactorService.confirmed_for(user)) or TwoFactorSession.passed?(conn, user) ->
        continue(conn)

      true ->
        UIRenderer.render_page(conn, "Escalated/Auth/TwoFactorChallenge", %{
          action: absolute_url(conn, RequireTwoFactor.challenge_path()),
          error: Phoenix.Flash.get(conn.assigns[:flash] || %{}, :error) || ""
        })
    end
  end

  def verify(conn, params) do
    user = conn.assigns[:current_user]

    with {:user, user} when not is_nil(user) <- {:user, user},
         {:enrolled, two_factor} when not is_nil(two_factor) <-
           {:enrolled, TwoFactorService.confirmed_for(user)} do
      attempt(conn, user, two_factor, params)
    else
      {:user, nil} -> unauthenticated(conn)
      {:enrolled, nil} -> continue(conn)
    end
  end

  defp attempt(conn, user, two_factor, params) do
    recovery = present(params["recovery_code"])
    code = present(params["code"])

    {field, result} =
      cond do
        recovery -> {"recovery_code", TwoFactorService.use_recovery_code(two_factor, recovery)}
        code -> {"code", TwoFactorService.verify_and_consume(two_factor, code)}
        true -> {"code", :missing}
      end

    case result do
      {:ok, _} ->
        conn
        |> configure_session(renew: true)
        |> TwoFactorSession.mark_passed(user)
        |> continue()

      :missing ->
        FormResponse.invalid(
          conn,
          %{"code" => "Enter the code from your authenticator app."},
          RequireTwoFactor.challenge_path()
        )

      :error ->
        Logger.notice("Escalated: two-factor challenge failed for user #{inspect(user.id)}")

        message =
          if field == "recovery_code",
            do: "That recovery code is not valid.",
            else: "That code is not valid."

        FormResponse.invalid(conn, %{field => message}, RequireTwoFactor.challenge_path())
    end
  end

  defp continue(conn) do
    {conn, path} = TwoFactorSession.pop_intended(conn, RequireTwoFactor.home_path())
    redirect(conn, to: path)
  end

  defp unauthenticated(conn) do
    conn |> put_status(401) |> json(%{error: "Authentication required"})
  end

  defp present(value) when is_binary(value) and byte_size(value) <= 64 do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  defp absolute_url(conn, path) do
    %URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port, path: path}
    |> URI.to_string()
  end
end
