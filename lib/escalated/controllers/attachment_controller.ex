defmodule Escalated.Controllers.AttachmentController do
  @moduledoc """
  Handles attachment downloads.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Schemas.Attachment

  def download(conn, %{"id" => id}) do
    repo = Escalated.repo()

    case repo.get(Attachment, id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Attachment not found"})

      attachment ->
        # For local storage, serve from the configured uploads directory.
        # For external backends (S3, etc.), redirect to the storage URL.
        case attachment.storage_backend do
          "local" ->
            upload_dir = Application.get_env(:escalated, :upload_dir, "priv/uploads")
            file_path = Path.join(upload_dir, attachment.storage_key)

            if File.exists?(file_path) do
              conn
              |> put_resp_content_type(attachment.mime_type || "application/octet-stream")
              |> put_resp_header(
                "content-disposition",
                ~s(attachment; filename="#{attachment.original_filename}")
              )
              |> send_file(200, file_path)
            else
              conn |> put_status(404) |> json(%{error: "File not found on disk"})
            end

          _external ->
            # For S3 or other external backends, the storage_key is the full URL
            conn |> redirect(external: attachment.storage_key)
        end
    end
  end
end
