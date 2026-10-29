defmodule Escalated.Controllers.Admin.TwoFactorController do
  @moduledoc """
  The signed-in staff member's own two-factor enrolment, serving the shared
  `Escalated/Admin/Settings/TwoFactor` page (escalated-laravel's
  `escalated.admin.two-factor.*`).

  - `index` renders `enabled`, `pending` and `required`.
  - `setup` creates a pending secret and flashes
    `two_factor_setup: %{qr_uri, recovery_codes}`.
  - `confirm` takes a 6-digit `code`, confirms the enrolment, counts as
    passing the challenge for this sign-in, and flashes
    `two_factor_confirmed: %{recovery_codes}`.
  - `disable` removes the enrolment.

  Open to every staff user, not only admins, and mounted only while
  two-factor is switched on. Secrets never appear in props.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.FormResponse
  alias Escalated.Plugs.RequireTwoFactor
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Services.TwoFactorService
  alias Escalated.TwoFactorSession

  def index(conn, _params) do
    user = conn.assigns.current_user

    UIRenderer.render_page(conn, "Escalated/Admin/Settings/TwoFactor", %{
      enabled: not is_nil(TwoFactorService.confirmed_for(user)),
      pending: not is_nil(TwoFactorService.pending_for(user)),
      required: TwoFactorService.required?()
    })
  end

  def setup(conn, _params) do
    case TwoFactorService.setup(conn.assigns.current_user) do
      {:ok, setup} ->
        conn
        |> put_flash(:two_factor_setup, setup)
        |> redirect(to: RequireTwoFactor.enrolment_path())

      {:error, :already_enabled} ->
        conn
        |> put_flash(
          :error,
          "Two-factor authentication is already enabled. Disable it first to set it up again."
        )
        |> redirect(to: RequireTwoFactor.enrolment_path())
    end
  end

  def confirm(conn, params) do
    user = conn.assigns.current_user
    code = if is_binary(params["code"]), do: params["code"], else: ""

    case TwoFactorService.confirm(user, code) do
      {:ok, recovery_codes} ->
        conn
        # The code just entered proves the second factor for this sign-in.
        |> TwoFactorSession.mark_passed(user)
        |> put_flash(:success, "Two-factor authentication enabled.")
        |> put_flash(:two_factor_confirmed, %{recovery_codes: recovery_codes})
        |> redirect(to: RequireTwoFactor.enrolment_path())

      {:error, :no_pending} ->
        invalid(conn, "No pending two-factor setup found.")

      {:error, :invalid_code} ->
        invalid(conn, "Invalid verification code.")
    end
  end

  def disable(conn, _params) do
    TwoFactorService.remove(conn.assigns.current_user.id)

    conn
    |> TwoFactorSession.forget()
    |> put_flash(:success, "Two-factor authentication disabled.")
    |> redirect(to: RequireTwoFactor.enrolment_path())
  end

  defp invalid(conn, message),
    do: FormResponse.invalid(conn, %{"code" => message}, RequireTwoFactor.enrolment_path())
end
