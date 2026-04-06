defmodule Escalated.Config do
  @moduledoc """
  Configuration struct for the Escalated helpdesk system.

  All values are read from application config under the `:escalated` key.
  """

  defstruct [
    :repo,
    :user_schema,
    :admin_check,
    :agent_check,
    route_prefix: "/support",
    table_prefix: "escalated_",
    ui_enabled: true,
    api_enabled: false,
    api_prefix: "/support/api/v1",
    default_priority: :medium,
    allow_customer_close: true,
    auto_close_resolved_after_days: 7,
    max_attachments: 5,
    max_attachment_size_kb: 10_240,
    sla: %{
      enabled: true,
      business_hours_only: true,
      business_hours: %{
        start: 9,
        end_hour: 17,
        timezone: "Etc/UTC",
        working_days: [1, 2, 3, 4, 5]
      }
    },
    notification_channels: [:email]
  ]

  @type t :: %__MODULE__{}

  @doc """
  Builds a Config struct from the application environment.
  """
  def from_env do
    fields =
      __MODULE__.__struct__()
      |> Map.from_struct()
      |> Enum.map(fn {key, default} ->
        {key, Application.get_env(:escalated, key, default)}
      end)

    struct!(__MODULE__, fields)
  end

  @doc """
  Returns true if the SLA system is enabled.
  """
  def sla_enabled?(%__MODULE__{sla: sla}), do: Map.get(sla, :enabled, false)

  @doc """
  Returns true if UI routes should be mounted.
  """
  def ui_enabled?(%__MODULE__{ui_enabled: val}), do: val == true
end
