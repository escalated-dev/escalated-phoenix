defmodule Escalated.AccessFeatures do
  @moduledoc """
  The install-level access switches (ADR 2026-10-29-configurable-access-features
  in escalated-developer-context): roles & permissions, two-factor
  authentication and single sign-on.

  Each switch is read from application config, falling back to its
  environment variable, and defaults to off:

      config :escalated,
        access: [roles_permissions: true, two_factor: false, sso: false]

  | Feature             | Config key                    | Env var                       |
  |---------------------|-------------------------------|-------------------------------|
  | Roles & permissions | `access: [roles_permissions]` | `ESCALATED_ROLES_PERMISSIONS` |
  | Two-factor          | `access: [two_factor]`        | `ESCALATED_TWO_FACTOR`        |
  | Single sign-on      | `access: [sso]`               | `ESCALATED_SSO`               |

  They are never read from the settings table and no admin screen changes
  them: each one changes who may sign in or what they may do, so a stored
  setting must not be able to flip it.

  Off, the feature's routes answer 404 (`Escalated.Plugs.EnsureFeatureEnabled`)
  and the shared `features.*` prop is false. A feature this package does not
  enforce yet is reported off whatever its switch says, so no screen claims to
  work before it does.
  """

  @features [:roles_permissions, :two_factor, :sso]

  # The features this port enforces. A switch for any other feature is
  # accepted but reported off until its enforcement lands.
  @enforced [:roles_permissions]

  @env %{
    roles_permissions: "ESCALATED_ROLES_PERMISSIONS",
    two_factor: "ESCALATED_TWO_FACTOR",
    sso: "ESCALATED_SSO"
  }

  @doc "The access feature names."
  def features, do: @features

  @doc "Whether roles & permissions is switched on (and so enforced)."
  def roles_permissions?, do: enabled?(:roles_permissions)

  @doc "Whether two-factor authentication is switched on (and so enforced)."
  def two_factor?, do: enabled?(:two_factor)

  @doc "Whether single sign-on is switched on (and so enforced)."
  def sso?, do: enabled?(:sso)

  @doc """
  Whether `feature` is on. Raises for a name that is not an access feature, so
  a typo in a router cannot leave a route open.
  """
  def enabled?(feature) when feature in @features,
    do: feature in @enforced and switch(feature)

  def enabled?(feature),
    do: raise(ArgumentError, "unknown Escalated access feature #{inspect(feature)}")

  @doc "The `features` entries shared with every page."
  def shared, do: Map.new(@features, &{&1, enabled?(&1)})

  # Config first (a keyword list or map under `:access`), then the env var.
  defp switch(feature) do
    access = Application.get_env(:escalated, :access, [])

    value =
      case fetch(access, feature) do
        {:ok, value} -> value
        :error -> System.get_env(Map.fetch!(@env, feature))
      end

    truthy?(value)
  end

  defp fetch(access, key) when is_list(access), do: Keyword.fetch(access, key)
  defp fetch(access, key) when is_map(access), do: Map.fetch(access, key)
  defp fetch(_access, _key), do: :error

  defp truthy?(value), do: value in [true, 1, "1", "true", "TRUE", "True", "on", "yes"]
end
