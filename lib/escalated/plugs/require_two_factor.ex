defmodule Escalated.Plugs.RequireTwoFactor do
  @moduledoc """
  While two-factor authentication is switched on
  (`Escalated.AccessFeatures.two_factor?/0`):

  - a user with a confirmed enrolment who has not passed the challenge in this
    sign-in (`Escalated.TwoFactorSession`) is redirected to
    `GET {prefix}/two-factor/challenge`;
  - when two-factor is required
    (`Escalated.Services.TwoFactorService.required?/0`), a staff user without
    an enrolment is redirected to the enrolment page,
    `GET {prefix}/admin/settings/two-factor`, and can reach nothing else.

  A JSON request (one that accepts JSON and is not an Inertia visit) gets 403
  with `two_factor_required: true` instead of a redirect. A GET is remembered
  and returned to afterwards.

  Piped after `EnsureAdmin` / `EnsureAgent` on every admin and agent route.
  Does nothing while the switch is off. The token API is not session-based
  and is not challenged. `Escalated.Plugs.RequireTwoFactor.Enrolment` runs on
  the enrolment routes themselves: it challenges, but does not send a user to
  the page they are already on.
  """
  import Plug.Conn
  @behaviour Plug

  alias Escalated.Services.TwoFactorService
  alias Escalated.TwoFactorSession

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts), do: check(conn, Keyword.get(opts, :enrolment, false))

  @doc false
  def check(conn, enrolment?) do
    user = conn.assigns[:current_user]

    cond do
      not Escalated.AccessFeatures.two_factor?() or is_nil(user) or not session?(conn) ->
        conn

      TwoFactorService.confirmed_for(user) ->
        if TwoFactorSession.passed?(conn, user),
          do: conn,
          else: deny(conn, challenge_path(), "Two-factor authentication is required.")

      not enrolment? and TwoFactorService.must_enrol?(user) ->
        deny(conn, enrolment_path(), "Set up two-factor authentication to continue.")

      true ->
        conn
    end
  end

  defp deny(conn, to, message) do
    if json_request?(conn) do
      conn
      |> put_status(403)
      |> Phoenix.Controller.json(%{message: message, two_factor_required: true})
      |> halt()
    else
      conn
      |> then(&if(&1.method == "GET", do: TwoFactorSession.put_intended(&1), else: &1))
      |> Phoenix.Controller.redirect(to: to)
      |> halt()
    end
  end

  # The mark lives in the session; a pipeline without one cannot be challenged.
  defp session?(conn), do: conn.private[:plug_session_fetch] == :done

  defp json_request?(conn) do
    get_req_header(conn, "x-inertia") != ["true"] and
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "json"))
  end

  @doc "`{prefix}/two-factor/challenge`"
  def challenge_path, do: prefix() <> "/two-factor/challenge"

  @doc "`{prefix}/admin/settings/two-factor`"
  def enrolment_path, do: prefix() <> "/admin/settings/two-factor"

  @doc "Where a user goes after the challenge when no page was remembered."
  def home_path, do: prefix() <> "/agent/dashboard"

  defp prefix, do: "/" <> String.trim(Escalated.config(:route_prefix, "/support"), "/")

  defmodule Enrolment do
    @moduledoc "`Escalated.Plugs.RequireTwoFactor` for the enrolment routes."
    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, _opts), do: Escalated.Plugs.RequireTwoFactor.check(conn, true)
  end
end
