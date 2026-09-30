defmodule Escalated.Controllers.AttachmentController do
  @moduledoc """
  Downloads attachments after checking their owning ticket and reply visibility.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Api.HostAuth
  alias Escalated.Permissions
  alias Escalated.Plugs.{ApiAuthenticate, GuestRateLimit}
  alias Escalated.Schemas.{Attachment, Reply, Ticket}
  alias Escalated.Services.GuestAccess
  alias Escalated.TicketAccess

  plug :authenticate

  defp authenticate(conn, opts) do
    case host_user(conn) do
      {:ok, user} -> conn |> assign(:current_user, user) |> ApiAuthenticate.call(opts)
      _ -> conn |> GuestRateLimit.call([]) |> authenticate_guest()
    end
  end

  defp host_user(%{assigns: %{current_user: user}}) when not is_nil(user), do: {:ok, user}

  defp host_user(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> HostAuth.validate(token)
      _ -> :error
    end
  end

  defp authenticate_guest(%{halted: true} = conn), do: conn

  defp authenticate_guest(conn) do
    token = GuestAccess.token(conn, conn.params)

    result =
      case GuestAccess.resolve_attachment(conn.params["download_token"], conn.params["id"]) do
        {:ok, _, _} = result ->
          result

        _ ->
          case GuestAccess.resolve(token) do
            {:ok, _, _} = result -> result
            _ -> GuestAccess.resolve(token, "chat")
          end
      end

    case result do
      {:ok, ticket, grant} -> assign(conn, :guest_attachment_access, {ticket, grant})
      _ -> conn |> put_status(401) |> json(%{error: "Authentication required"}) |> halt()
    end
  end

  def download(conn, %{"id" => id}) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("x-content-type-options", "nosniff")

    user = conn.assigns[:current_user]

    guest = conn.assigns[:guest_attachment_access]

    if is_nil(TicketAccess.user_id(user)) and is_nil(guest) do
      conn |> put_status(401) |> json(%{error: "Authentication required"})
    else
      with {key, ""} when key > 0 and key <= 9_223_372_036_854_775_807 <- Integer.parse(id),
           %Attachment{} = attachment <- Escalated.repo().get(Attachment, key),
           {%Ticket{} = ticket, internal?} <- owner(attachment),
           true <-
             (not is_nil(user) and Permissions.agent?(user)) or
               (not internal? and
                  (TicketAccess.requester?(ticket, user) or guest_owns?(guest, ticket))) do
        serve(conn, attachment)
      else
        _ -> not_found(conn)
      end
    end
  end

  defp guest_owns?({%Ticket{id: id}, _grant}, %Ticket{id: id}), do: true
  defp guest_owns?(_, _), do: false

  defp owner(%Attachment{reply_id: reply_id, ticket_id: ticket_id}) when not is_nil(reply_id) do
    case Escalated.repo().get(Reply, reply_id) do
      %Reply{} = reply when is_nil(ticket_id) or ticket_id == reply.ticket_id ->
        {Escalated.repo().get(Ticket, reply.ticket_id), reply.is_internal != false}

      _ ->
        nil
    end
  end

  defp owner(%Attachment{ticket_id: ticket_id}) when not is_nil(ticket_id),
    do: {Escalated.repo().get(Ticket, ticket_id), false}

  defp owner(_), do: nil

  defp serve(conn, %Attachment{storage_backend: "local"} = attachment) do
    root = Application.get_env(:escalated, :upload_dir, "priv/uploads") |> Path.expand()
    path = Path.expand(attachment.storage_key, root)
    relative = Path.relative_to(path, root)

    if Path.type(relative) == :relative and ".." not in Path.split(relative) and
         regular_file_without_links?(root, Path.split(relative)) do
      send_download(conn, {:file, path},
        filename: attachment.original_filename,
        content_type: attachment.mime_type || "application/octet-stream"
      )
    else
      not_found(conn)
    end
  end

  defp serve(conn, attachment) do
    callback = Escalated.config(:attachment_download_url)

    ttl =
      case conn.assigns[:guest_attachment_access] do
        {_ticket, grant} -> min(300, DateTime.diff(grant.expires_at, GuestAccess.now(), :second))
        _ -> 300
      end

    result =
      if ttl > 0 and is_function(callback, 2), do: callback.(attachment, ttl), else: :unavailable

    case result do
      {:ok, url} when is_binary(url) ->
        case URI.parse(url) do
          %URI{scheme: "https", host: host, userinfo: nil} when is_binary(host) and host != "" ->
            redirect(conn, external: url)

          _ ->
            unavailable(conn)
        end

      _ ->
        unavailable(conn)
    end
  end

  # Do not follow a symlink within the upload tree to another file or directory.
  # The configured root and its filesystem must remain under host administration.
  defp regular_file_without_links?(root, [part]) do
    match?({:ok, %File.Stat{type: :regular}}, File.lstat(Path.join(root, part)))
  end

  defp regular_file_without_links?(root, [part | rest]) do
    path = Path.join(root, part)

    match?({:ok, %File.Stat{type: :directory}}, File.lstat(path)) and
      regular_file_without_links?(path, rest)
  end

  defp regular_file_without_links?(_, _), do: false

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "Attachment not found"})

  defp unavailable(conn),
    do: conn |> put_status(503) |> json(%{error: "Private attachment storage is not configured"})
end
