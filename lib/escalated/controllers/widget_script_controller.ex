defmodule Escalated.Controllers.WidgetScriptController do
  @moduledoc """
  Serves the standalone widget bundle at `{prefix}/widget/embed.js`, so any
  site can load the widget with a `<script>` tag pointing at this install.

  The bundle is `dist/widget/escalated-widget.js` from the
  `@escalated-dev/escalated` npm package, vendored at
  `priv/static/widget/escalated-widget.js`.
  """
  use Phoenix.Controller, formats: [:js]
  import Plug.Conn

  @bundle "static/widget/escalated-widget.js"

  def show(conn, _params) do
    with path when is_binary(path) <- bundle_path(),
         {:ok, body} <- File.read(path) do
      etag = ~s("#{:crypto.hash(:md5, body) |> Base.encode16(case: :lower)}")

      conn =
        conn
        # The bundle is public. Plug.CSRFProtection otherwise refuses to send
        # JavaScript to a <script> tag on another site, the whole point here.
        |> put_private(:plug_skip_csrf_protection, true)
        |> put_resp_header("content-type", "application/javascript; charset=utf-8")
        |> put_resp_header("cache-control", "public, max-age=3600")
        |> put_resp_header("etag", etag)
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("cross-origin-resource-policy", "cross-origin")
        |> put_resp_header("access-control-allow-origin", "*")

      if etag in if_none_match(conn),
        do: send_resp(conn, 304, ""),
        else: send_resp(conn, 200, body)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  defp bundle_path do
    case :code.priv_dir(:escalated) do
      {:error, _} -> nil
      dir -> Path.join(to_string(dir), @bundle)
    end
  end

  defp if_none_match(conn) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&(&1 |> String.trim() |> String.replace_prefix("W/", "")))
  end
end
