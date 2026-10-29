defmodule Escalated.Plugs.EnsureFeatureEnabled do
  @moduledoc """
  Answers 404 for routes whose access feature is switched off
  (`Escalated.AccessFeatures`), the way disabled knowledge-base and widget
  routes do. The routes stay mounted, so the switch is read on each request.

  As a plug with an option:

      plug Escalated.Plugs.EnsureFeatureEnabled, feature: :roles_permissions

  Phoenix's `pipe_through` takes modules without options, so each feature also
  has a module of its own for router scopes:

      pipe_through Escalated.Plugs.EnsureFeatureEnabled.RolesPermissions
      pipe_through Escalated.Plugs.EnsureFeatureEnabled.TwoFactor
      pipe_through Escalated.Plugs.EnsureFeatureEnabled.Sso
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts) do
    feature = Keyword.fetch!(opts, :feature)
    # Raises for an unknown name at init, not on the first request.
    _ = Escalated.AccessFeatures.enabled?(feature)
    feature
  end

  @impl true
  def call(conn, feature), do: gate(conn, feature)

  @doc false
  def gate(conn, feature) do
    if Escalated.AccessFeatures.enabled?(feature) do
      conn
    else
      conn
      |> put_status(404)
      |> Phoenix.Controller.json(%{error: "Not found"})
      |> halt()
    end
  end

  for {name, feature} <- [RolesPermissions: :roles_permissions, TwoFactor: :two_factor, Sso: :sso] do
    defmodule Module.concat(__MODULE__, name) do
      @moduledoc "`Escalated.Plugs.EnsureFeatureEnabled` for `#{inspect(feature)}`."
      @behaviour Plug
      @feature feature

      @impl true
      def init(opts), do: opts

      @impl true
      def call(conn, _opts), do: Escalated.Plugs.EnsureFeatureEnabled.gate(conn, @feature)
    end
  end
end
