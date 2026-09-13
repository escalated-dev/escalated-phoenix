defmodule Escalated.Test.Router do
  @moduledoc false

  # A host router, written the way a Phoenix app mounts the package.
  #
  # Controller tests that call an action function directly cannot see a route
  # that is missing, shadowed or pointed at the wrong action: the function is
  # there whether or not anything reaches it. Requests sent through this router
  # take the path a browser request does, so they can.
  #
  # The pipeline is the smallest one the admin pages need: JSON bodies parsed
  # the way an Inertia form visit sends them, a session and flash for the
  # redirect-with-errors convention, and the Inertia plug itself.
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
  end

  scope "/" do
    pipe_through :browser
    escalated_routes("/support")
  end
end
