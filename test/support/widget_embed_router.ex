defmodule Escalated.Test.WidgetEmbedRouter do
  @moduledoc false

  # A host router mounted the way the README recommends for cross-origin
  # embedding: the widget routes get a pipeline of their own in which
  # Escalated.Plugs.WidgetCors runs before the host's CSRF check, and every
  # other route keeps the host's usual browser pipeline. Both pipelines read
  # the signed-in user from the session, the way a host's auth plug does, so
  # the tests can tell whether an embedded request acted as that user.
  use Phoenix.Router
  use Escalated.Router

  pipeline :browser do
    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: ["*/*"],
      json_decoder: Jason

    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :fetch_signed_in_user
  end

  pipeline :escalated_widget do
    plug Plug.Parsers,
      parsers: [:urlencoded, :json],
      pass: ["*/*"],
      json_decoder: Jason

    plug :fetch_session
    plug Escalated.Plugs.WidgetCors
    plug :protect_from_forgery
    plug :fetch_signed_in_user
  end

  scope "/" do
    pipe_through :escalated_widget
    escalated_widget_routes("/support")
  end

  scope "/" do
    pipe_through :browser
    escalated_routes("/support", widget: false)
  end

  def fetch_signed_in_user(conn, _opts) do
    case Plug.Conn.get_session(conn, "signed_in_user") do
      nil -> conn
      user -> Plug.Conn.assign(conn, :current_user, user)
    end
  end
end
