defmodule Escalated.Services.Email.Inbound.LocalFileStorage do
  @moduledoc """
  Reference `AttachmentDownloader` storage for hosts without cloud
  storage — writes to the local filesystem under a configured root.
  Files are prefixed with a UTC timestamp (with microseconds) to avoid
  collisions between uploads with the same original filename.

  Host apps with durable cloud storage needs should build their own
  storage function-map with `put: fn filename, content, content_type -> ...`
  and pass it directly to `AttachmentDownloader.download/6` instead
  of using this module.
  """

  @doc """
  Returns a storage function-map writing files under `root`. Creates
  the root directory if it doesn't already exist.
  """
  @spec new(String.t()) :: map()
  def new(root) when is_binary(root) and root != "" do
    File.mkdir_p!(root)

    %{
      put: fn filename, content, _content_type ->
        now = DateTime.utc_now()

        prefix =
          DateTime.to_iso8601(now, :basic) <> "-" <> Integer.to_string(now.microsecond |> elem(0))

        stored_name = "#{prefix}-#{filename}"
        full_path = Path.join(root, stored_name)

        case File.write(full_path, content) do
          :ok -> {:ok, full_path}
          {:error, reason} -> {:error, {:write_failed, full_path, reason}}
        end
      end,
      backend_name: "local"
    }
  end

  def new(""), do: raise(ArgumentError, "Local file storage root is required")
  def new(nil), do: raise(ArgumentError, "Local file storage root is required")
end
