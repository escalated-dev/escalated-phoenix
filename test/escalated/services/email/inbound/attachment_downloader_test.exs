defmodule Escalated.Services.Email.Inbound.AttachmentDownloaderTest do
  use ExUnit.Case, async: true

  alias Escalated.Services.Email.Inbound.AttachmentDownloader
  alias Escalated.Services.Email.Inbound.LocalFileStorage

  # Canned HTTP responses via a {module, fun} indirection so the tests
  # don't need a live HTTP server.
  defmodule FakeHttp do
    def get(:get, _url, _headers) do
      Process.get(:__fake_response__) || {:ok, %{status: 200, body: "ok", headers: []}}
    end
  end

  defmodule FailHttp do
    def get(:get, _url, _headers), do: {:error, :econnrefused}
  end

  defmodule SequencedHttp do
    @moduledoc """
    Returns status codes from `:__ad_sequence__` in order. Use
    `Process.put(:__ad_sequence__, [200, 500, 200])` to stage a
    mixed-outcome batch for `download_all` tests.
    """
    def get(:get, _url, _headers) do
      [status | rest] = Process.get(:__ad_sequence__, [200])
      Process.put(:__ad_sequence__, rest == [] and [200] or rest)
      {:ok, %{status: status, body: "ok", headers: []}}
    end
  end

  defp stub_response(resp), do: Process.put(:__fake_response__, resp)

  defp fake_storage(opts \\ []) do
    agent = :ets.new(:fake_storage, [:public, :set])
    return_err = Keyword.get(opts, :error)
    return_path = Keyword.get(opts, :path, "/stored/path")

    %{
      put: fn filename, content, content_type ->
        :ets.insert(agent, {:put, {filename, content, content_type}})

        if return_err, do: {:error, return_err}, else: {:ok, return_path}
      end,
      _ets: agent
    }
  end

  defp fake_writer(opts \\ []) do
    agent = :ets.new(:fake_writer, [:public, :set])
    return_err = Keyword.get(opts, :error)
    return_attachment = Keyword.get(opts, :attachment, %{id: 99})

    %{
      create_attachment: fn attrs ->
        :ets.insert(agent, {:create, attrs})
        if return_err, do: {:error, return_err}, else: {:ok, return_attachment}
      end,
      _ets: agent
    }
  end

  defp pending(overrides \\ %{}) do
    Map.merge(
      %{
        name: "report.pdf",
        content_type: "application/pdf",
        size_bytes: 9,
        download_url: "https://provider/att/1"
      },
      overrides
    )
  end

  defp options(overrides \\ %{}) do
    Map.merge(%{http_client: {FakeHttp, :get}}, overrides)
  end

  describe "download/6" do
    test "happy path persists attachment" do
      stub_response(
        {:ok, %{status: 200, body: "hello pdf", headers: [{"Content-Type", "application/pdf"}]}}
      )
      storage = fake_storage(path: "/store/report.pdf")
      writer = fake_writer(attachment: %{id: 1, original_filename: "report.pdf"})

      assert {:ok, attachment} =
               AttachmentDownloader.download(pending(), 42, nil, storage, writer, options())

      assert attachment.id == 1
      # Storage was called with the filename + content.
      [{:put, {fname, body, ctype}}] = :ets.tab2list(storage._ets)
      assert fname == "report.pdf"
      assert body == "hello pdf"
      assert ctype == "application/pdf"
      # Writer got the right attrs.
      [{:create, attrs}] = :ets.tab2list(writer._ets)
      assert attrs.original_filename == "report.pdf"
      assert attrs.ticket_id == 42
      assert attrs.reply_id == nil
      assert attrs.size == byte_size("hello pdf")
      assert attrs.storage_key == "/store/report.pdf"
    end

    test "sets reply_id when provided" do
      stub_response({:ok, %{status: 200, body: "x", headers: []}})
      storage = fake_storage()
      writer = fake_writer()

      assert {:ok, _} =
               AttachmentDownloader.download(pending(), 42, 7, storage, writer, options())

      [{:create, attrs}] = :ets.tab2list(writer._ets)
      assert attrs.reply_id == 7
    end

    test "returns :missing_download_url when URL is absent" do
      storage = fake_storage()
      writer = fake_writer()

      assert {:error, :missing_download_url} =
               AttachmentDownloader.download(
                 pending(%{download_url: ""}),
                 1,
                 nil,
                 storage,
                 writer,
                 options()
               )

      assert :ets.tab2list(writer._ets) == []
    end

    test "returns {:http_status, ...} on 404" do
      stub_response({:ok, %{status: 404, body: "", headers: []}})
      storage = fake_storage()
      writer = fake_writer()

      assert {:error, {:http_status, 404}} =
               AttachmentDownloader.download(pending(), 1, nil, storage, writer, options())

      assert :ets.tab2list(storage._ets) == []
      assert :ets.tab2list(writer._ets) == []
    end

    test "returns :too_large when body exceeds max_bytes" do
      stub_response({:ok, %{status: 200, body: String.duplicate("x", 100), headers: []}})
      storage = fake_storage()
      writer = fake_writer()

      assert {:error, {:too_large, 100, 10}} =
               AttachmentDownloader.download(
                 pending(),
                 1,
                 nil,
                 storage,
                 writer,
                 options(%{max_bytes: 10})
               )

      assert :ets.tab2list(writer._ets) == []
    end

    test "propagates HTTP errors from the client" do
      storage = fake_storage()
      writer = fake_writer()

      assert {:error, :econnrefused} =
               AttachmentDownloader.download(
                 pending(),
                 1,
                 nil,
                 storage,
                 writer,
                 %{http_client: {FailHttp, :get}}
               )
    end

    test "falls back to response Content-Type when pending content_type is blank" do
      stub_response(
        {:ok, %{status: 200, body: <<1, 2, 3>>, headers: [{"Content-Type", "image/png"}]}}
      )
      storage = fake_storage()
      writer = fake_writer()

      assert {:ok, _} =
               AttachmentDownloader.download(
                 pending(%{content_type: ""}),
                 1,
                 nil,
                 storage,
                 writer,
                 options()
               )

      [{:create, attrs}] = :ets.tab2list(writer._ets)
      assert attrs.mime_type == "image/png"
    end

    test "neutralizes path-traversal filenames" do
      stub_response({:ok, %{status: 200, body: "x", headers: []}})
      storage = fake_storage()
      writer = fake_writer()

      assert {:ok, _} =
               AttachmentDownloader.download(
                 pending(%{name: "../../etc/passwd"}),
                 1,
                 nil,
                 storage,
                 writer,
                 options()
               )

      [{:put, {fname, _, _}}] = :ets.tab2list(storage._ets)
      assert fname == "passwd"
    end
  end

  describe "download_all/6" do
    test "continues past per-attachment failures" do
      # Stage a 200/500/200 sequence so the middle attachment fails
      # while the other two succeed.
      Process.put(:__ad_sequence__, [200, 500, 200])

      storage = fake_storage()
      writer = fake_writer()

      results =
        AttachmentDownloader.download_all(
          [
            pending(%{download_url: "https://x/1"}),
            pending(%{download_url: "https://x/2"}),
            pending(%{download_url: "https://x/3"})
          ],
          1,
          nil,
          storage,
          writer,
          %{http_client: {SequencedHttp, :get}}
        )

      assert length(results) == 3
      assert Enum.at(results, 0).error == nil
      assert Enum.at(results, 1).error == {:http_status, 500}
      assert Enum.at(results, 2).error == nil
    end
  end

  describe "safe_filename/1" do
    test "strips path traversal" do
      assert AttachmentDownloader.safe_filename("../../etc/passwd") == "passwd"
      assert AttachmentDownloader.safe_filename("/tmp/evil.txt") == "evil.txt"
      assert AttachmentDownloader.safe_filename("..") == "attachment"
      assert AttachmentDownloader.safe_filename(".") == "attachment"
      assert AttachmentDownloader.safe_filename("") == "attachment"
      assert AttachmentDownloader.safe_filename(nil) == "attachment"
    end
  end

  describe "LocalFileStorage" do
    @tag :tmp_dir
    test "new/1 writes files under the root", %{tmp_dir: tmp} do
      root = Path.join(tmp, "attachments")
      storage = LocalFileStorage.new(root)

      assert {:ok, path} = storage.put.("hello.txt", "payload", "text/plain")
      assert String.starts_with?(path, root)
      assert String.ends_with?(path, "hello.txt")
      assert File.read!(path) == "payload"
    end

    test "new/1 rejects empty root" do
      assert_raise ArgumentError, fn -> LocalFileStorage.new("") end
      assert_raise ArgumentError, fn -> LocalFileStorage.new(nil) end
    end

    @tag :tmp_dir
    test "put produces unique paths for consecutive calls", %{tmp_dir: tmp} do
      storage = LocalFileStorage.new(tmp)

      {:ok, p1} = storage.put.("x.txt", "a", "text/plain")
      # Small sleep so the microsecond prefix differs.
      Process.sleep(2)
      {:ok, p2} = storage.put.("x.txt", "b", "text/plain")

      assert p1 != p2
    end
  end
end
