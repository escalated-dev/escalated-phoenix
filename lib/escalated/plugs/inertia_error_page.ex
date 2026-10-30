defmodule Escalated.Plugs.InertiaErrorPage do
  @moduledoc """
  Answers an Inertia visit to one of Escalated's routes that ends in 403, 404,
  419, 429, 500 or 503 with the shared frontend's `Escalated/Error` page.

  Without it the Inertia client gets a JSON error body or the host's HTML
  error page back, and can only show it in a modal over the screen the user
  was on.

  `escalated_routes/2` puts this plug on its scope. It registers a
  `before_send` callback, so it sees every way such a visit can end: a plug
  that halts with a refusal, a controller that answers with an error status,
  and an exception the host's endpoint renders (`render_errors`), which sends
  the conn the exception was raised with.

  The props are the ones Rails and Laravel send: `status` and a generic
  `message`. A controller's, plug's or exception's own text never reaches the
  page. Left alone:

    * requests without `x-inertia` (full page loads, JSON and API clients);
    * the JSON API, widget, webhook, inbound-email and single sign-on
      controllers;
    * responses that are already Inertia pages;
    * a 500 while the endpoint's `debug_errors` is on, so `Plug.Debugger`'s
      page stays where a developer wants it;
    * everything while `ui_enabled` is false.
  """

  @behaviour Plug

  @page "Escalated/Error"

  @messages %{
    403 => "You are not authorized to perform this action.",
    404 => "The requested resource was not found.",
    419 => "Your session has expired. Refresh the page and try again.",
    429 => "Too many requests. Wait a moment and try again.",
    500 => "Something went wrong on our end.",
    503 => "The service is temporarily unavailable. Try again shortly."
  }

  # Controllers that answer API, widget and machine clients. They speak JSON
  # (or redirect to an identity provider), never Inertia.
  @skipped_controllers [
    Escalated.Controllers.InboundEmailController,
    Escalated.Controllers.SsoController,
    Escalated.Controllers.WidgetController,
    Escalated.Controllers.WidgetChatController,
    Escalated.Controllers.WidgetScriptController
  ]

  @skipped_namespaces [
    "Elixir.Escalated.Controllers.Api.",
    "Elixir.Escalated.Controllers.Webhooks."
  ]

  @doc "The statuses the page renders, mapped to their messages."
  def messages, do: @messages

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if inertia_visit?(conn) and Escalated.config(:ui_enabled, true) and
         not skipped_controller?(conn) do
      Plug.Conn.register_before_send(conn, &render_error_page/1)
    else
      conn
    end
  end

  @doc false
  def render_error_page(%Plug.Conn{state: :set, status: status} = conn)
      when is_map_key(@messages, status) do
    cond do
      Plug.Conn.get_resp_header(conn, "x-inertia") != [] -> conn
      status == 500 and debug_errors?(conn) -> conn
      true -> error_page(conn, status)
    end
  end

  def render_error_page(conn), do: conn

  defp error_page(conn, status) do
    page = %{
      component: @page,
      props: %{status: status, message: Map.fetch!(@messages, status)},
      url: request_path(conn),
      version: conn.private[:inertia_version],
      encryptHistory: conn.private[:inertia_encrypt_history] || false,
      clearHistory: conn.private[:inertia_clear_history] || false
    }

    %{conn | resp_body: Jason.encode!(page)}
    |> Plug.Conn.put_resp_header("content-type", "application/json; charset=utf-8")
    |> Plug.Conn.put_resp_header("x-inertia", "true")
    |> Plug.Conn.put_resp_header("vary", "X-Inertia")
  end

  defp inertia_visit?(conn), do: Plug.Conn.get_req_header(conn, "x-inertia") != []

  defp skipped_controller?(conn) do
    case conn.private[:phoenix_controller] do
      nil ->
        false

      controller ->
        name = Atom.to_string(controller)

        controller in @skipped_controllers or
          Enum.any?(@skipped_namespaces, &String.starts_with?(name, &1))
    end
  end

  defp debug_errors?(conn) do
    case conn.private[:phoenix_endpoint] do
      nil -> false
      endpoint -> endpoint.config(:debug_errors) == true
    end
  end

  defp request_path(%{query_string: ""} = conn), do: conn.request_path
  defp request_path(conn), do: conn.request_path <> "?" <> conn.query_string
end
