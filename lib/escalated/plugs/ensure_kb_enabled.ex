defmodule Escalated.Plugs.EnsureKbEnabled do
  @moduledoc """
  Plug that guards knowledge base routes.

  Returns a 404 response when the knowledge base feature is disabled
  in the Escalated configuration.

  ## Configuration

      config :escalated,
        knowledge_base_enabled: true

  When `knowledge_base_enabled` is `false` (the default), all requests
  piped through this plug will receive a 404 Not Found response.
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    config = Escalated.configuration()

    if Escalated.Config.knowledge_base_enabled?(config) do
      conn
    else
      conn
      |> put_status(404)
      |> Phoenix.Controller.json(%{error: "Knowledge base is not enabled"})
      |> halt()
    end
  end
end
