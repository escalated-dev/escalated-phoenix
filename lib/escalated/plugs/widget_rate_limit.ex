defmodule Escalated.Plugs.WidgetRateLimit do
  @moduledoc "Throttles public widget and chat endpoints using `:widget_rate_limit`."
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Escalated.Plugs.PublicRateLimit.call(conn, bucket: :widget, config: :widget_rate_limit)
  end
end
