defmodule Escalated.Controllers.AttachmentControllerTest do
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{Attachment, Reply, Ticket}
  alias Escalated.Test.Router

  setup do
    keys = [:upload_dir, :attachment_download_url, :agent_check, :api_token_validator]
    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})

    root =
      Path.join(System.tmp_dir!(), "escalated-attachment-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    File.write!(Path.join(root, "parcel.txt"), "Private parcel photo")
    Application.put_env(:escalated, :upload_dir, root)
    Application.put_env(:escalated, :agent_check, fn user -> user[:is_agent] == true end)
    Application.delete_env(:escalated, :attachment_download_url)
    Application.delete_env(:escalated, :api_token_validator)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)

      File.rm_rf!(root)
    end)

    ticket =
      Escalated.repo().insert!(
        Ticket.changeset(%Ticket{}, %{
          subject: "Parcel",
          description: "Details",
          requester_id: 101
        })
      )

    attachment = attachment!(%{ticket_id: ticket.id})
    %{root: root, ticket: ticket, attachment: attachment}
  end

  defp attachment!(attrs) do
    Escalated.repo().insert!(
      Attachment.changeset(
        %Attachment{},
        Map.merge(
          %{
            original_filename: "parcel.txt",
            storage_key: "parcel.txt",
            mime_type: "text/plain",
            size: 20
          },
          attrs
        )
      )
    )
  end

  defp download(id, user, token \\ nil) do
    conn = conn(:get, "/support/attachments/#{id}/download") |> init_test_session(%{})
    conn = if user, do: assign(conn, :current_user, user), else: conn
    conn = if token, do: put_req_header(conn, "authorization", "Bearer " <> token), else: conn
    Router.call(conn, Router.init([]))
  end

  test "serves requester and staff while refusing anonymous and unrelated users", %{attachment: a} do
    assert download(a.id, nil).status == 401
    assert download(a.id, %{id: 202}).status == 404

    for user <- [%{id: 101}, %{id: "101"}, %{id: 900, is_agent: true}] do
      response = download(a.id, user)
      assert response.status == 200
      assert response.resp_body == "Private parcel photo"
      assert get_resp_header(response, "cache-control") == ["no-store"]
      assert get_resp_header(response, "referrer-policy") == ["no-referrer"]
      assert get_resp_header(response, "x-content-type-options") == ["nosniff"]
    end

    assert download("not-an-id", %{id: 101}).status == 404
    assert download("999999999999999999999999", %{id: 101}).status == 404
  end

  test "uses the host bearer validator and rechecks membership each download", %{attachment: a} do
    Application.put_env(:escalated, :api_token_validator, fn
      "owner" -> {:ok, %{id: 101}}
      _ -> :error
    end)

    assert download(a.id, nil, "owner").status == 200
    assert download(a.id, nil, "wrong").status == 401
    Application.put_env(:escalated, :api_token_validator, fn _ -> :error end)
    assert download(a.id, nil, "owner").status == 401
  end

  test "resolves reply ownership and keeps internal attachments staff-only", %{ticket: ticket} do
    public =
      Escalated.repo().insert!(
        Reply.changeset(%Reply{}, %{ticket_id: ticket.id, body: "Public", is_internal: false})
      )

    private =
      Escalated.repo().insert!(
        Reply.changeset(%Reply{}, %{ticket_id: ticket.id, body: "Internal", is_internal: true})
      )

    public_file = attachment!(%{reply_id: public.id})
    private_file = attachment!(%{ticket_id: ticket.id, reply_id: private.id})
    assert download(public_file.id, %{id: 101}).status == 200
    assert download(private_file.id, %{id: 101}).status == 404
    assert download(private_file.id, %{id: 900, is_agent: true}).status == 200
    orphan = attachment!(%{})
    assert download(orphan.id, %{id: 900, is_agent: true}).status == 404

    other =
      Escalated.repo().insert!(
        Ticket.changeset(%Ticket{}, %{subject: "Other", description: "Other", requester_id: 202})
      )

    mismatch = attachment!(%{ticket_id: other.id, reply_id: public.id})
    assert download(mismatch.id, %{id: 900, is_agent: true}).status == 404
  end

  test "confines local files to regular files inside the configured upload directory", %{
    root: root,
    ticket: ticket
  } do
    File.ln_s!(Path.join(root, "parcel.txt"), Path.join(root, "link.txt"))

    for key <- ["../outside.txt", "/etc/passwd", "missing.txt", "link.txt", "."] do
      a = attachment!(%{ticket_id: ticket.id, storage_key: key})
      assert download(a.id, %{id: 101}).status == 404
    end

    absolute =
      attachment!(%{
        ticket_id: ticket.id,
        storage_key: Path.join(root, "parcel.txt"),
        original_filename: "quote\"\r\nname.txt"
      })

    response = download(absolute.id, %{id: 101})
    assert response.status == 200
    [disposition] = get_resp_header(response, "content-disposition")
    refute disposition =~ "\r"
    refute disposition =~ "\n"
  end

  test "uses a host private URL callback only after authorization", %{ticket: ticket} do
    a =
      attachment!(%{
        ticket_id: ticket.id,
        storage_backend: "s3",
        storage_key: "https://old-public.example/parcel"
      })

    assert download(a.id, %{id: 101}).status == 503
    parent = self()

    Application.put_env(:escalated, :attachment_download_url, fn attachment, seconds ->
      send(parent, {:signed, attachment.id, seconds})
      {:ok, "https://private.example/object?signature=short-lived"}
    end)

    assert download(a.id, %{id: 202}).status == 404
    refute_received {:signed, _, _}
    response = download(a.id, %{id: 101})
    assert response.status == 302
    assert_received {:signed, _, 300}

    assert get_resp_header(response, "location") == [
             "https://private.example/object?signature=short-lived"
           ]

    Application.put_env(:escalated, :attachment_download_url, fn _, _ ->
      {:ok, "javascript:alert(1)"}
    end)

    assert download(a.id, %{id: 101}).status == 503
  end
end
