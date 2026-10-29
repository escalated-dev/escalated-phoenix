defmodule Escalated.Test.SharedPropsRouter do
  @moduledoc false

  # Escalated.Test.Router plus `Escalated.Plugs.ShareInertiaData` in the host
  # pipeline, the way the README has hosts mount it, so a test can read the
  # shared `escalated` props (features, permissions) off a rendered page.
  use Phoenix.Router
  use Escalated.Router

  pipeline :browser do
    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: ["*/*"],
      json_decoder: Jason

    plug :fetch_session
    plug :fetch_flash
    plug Inertia.Plug
    plug Escalated.Plugs.ShareInertiaData
  end

  scope "/" do
    pipe_through :browser
    escalated_routes("/support", api: true)
  end
end
