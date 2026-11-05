defmodule Escalated.Plugs.ApplyEmbedContext do
  @moduledoc """
  Runs on the admin routes while they are embedded in the host's admin panel
  (ADR 2026-11-05-embeddable-admin), and on no other route:
  `escalated_routes/2` puts it first in the embedded scope.

    * Marks the request as embedded, so the shared `escalated.embed` prop
      says `enabled: true` and names the route. Props the host's pipeline
      already shared (`Escalated.Plugs.ShareInertiaData` runs before this
      scope) are updated in place.
    * `root_view` set: renders the response in that root layout (the host's
      admin template, for server-rendered hosts).
    * iframe mode: registers a `before_send/2` callback that drops
      `X-Frame-Options` and adds `Content-Security-Policy: frame-ancestors
      'self' <origins>` (`Escalated.Embed.decorate_response/1`). Plug runs
      those callbacks newest first, so this one, registered before the host's
      embed middleware and Escalated's controllers, runs after theirs: they
      cannot put the header back. Layout mode adds no header.
  """
  @behaviour Plug

  alias Escalated.Embed

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> Embed.mark()
    |> put_root_view()
    |> Embed.reshare()
    |> Plug.Conn.register_before_send(&Embed.decorate_response/1)
  end

  defp put_root_view(conn) do
    case Embed.root_view() do
      nil -> conn
      layout -> Phoenix.Controller.put_root_layout(conn, html: layout)
    end
  end
end
