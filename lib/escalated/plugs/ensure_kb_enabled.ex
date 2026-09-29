defmodule Escalated.Plugs.EnsureKbEnabled do
  @moduledoc """
  Plug that guards knowledge base routes.

  Returns 404 when the knowledge base is disabled, or when an anonymous
  visitor requests a nonpublic knowledge base. Persisted admin settings
  override host configuration.

  ## Configuration

      config :escalated,
        knowledge_base_enabled: true,
        knowledge_base_public: true

  When `knowledge_base_enabled` is `false` (the default), all requests
  piped through this plug will receive a 404 Not Found response.
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    settings = Escalated.Services.GeneralSettings.all()

    if settings["knowledge_base_enabled"] and
         (settings["knowledge_base_public"] or not is_nil(conn.assigns[:current_user])) do
      conn
    else
      conn
      |> put_status(404)
      |> Phoenix.Controller.json(%{error: "Knowledge base is not enabled"})
      |> halt()
    end
  end
end
