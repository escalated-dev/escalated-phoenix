defmodule Escalated.TicketMergeAndBulkTest do
  @moduledoc """
  Ticket merge (escalated-laravel's TicketMergeService and
  TicketMergeController) and bulk actions (its BulkActionController), through
  the routes the shared TicketMergeDialog and BulkActionBar call.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{Attachment, Department, Reply, Tag, Ticket, WebhookDelivery}
  alias Escalated.Services.{TicketMergeService, TicketService}
  alias Escalated.Test.Router
  alias Escalated.Webhooks

  @admin %{id: 1, is_admin: true}
  @agent %{id: 2, is_agent: true}

  defp repo, do: Escalated.repo()

  setup do
    Application.put_env(:escalated, :webhook_sync, true)

    Application.put_env(:escalated, :webhook_http_client, fn _url, _headers, _body ->
      {:ok, %{status: 200, body: "ok"}}
    end)

    on_exit(fn ->
      Application.delete_env(:escalated, :webhook_sync)
      Application.delete_env(:escalated, :webhook_http_client)
    end)

    :ok
  end

  describe "merge" do
    test "moves the replies, notes both tickets and closes the source into the target" do
      source = ticket!("Printer jammed")
      target = ticket!("Printer broken")

      {:ok, reply} = TicketService.reply(source, %{body: "It beeps", is_internal: false})
      {:ok, note} = TicketService.reply(source, %{body: "Checked toner", is_internal: true})

      attachment =
        %Attachment{}
        |> Attachment.changeset(%{
          original_filename: "beep.txt",
          storage_key: "k/beep.txt",
          size: 4,
          ticket_id: source.id,
          reply_id: reply.id
        })
        |> repo().insert!()

      subscribe(["ticket.status_changed", "ticket.closed"])

      conn =
        visit(:post, "/support/admin/tickets/#{source.reference}/merge", @admin, %{
          "target_reference" => target.reference
        })

      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/support/admin/tickets/#{source.reference}"]
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ target.reference

      closed = repo().get!(Ticket, source.id)
      assert closed.status == "closed"
      assert closed.closed_at
      assert closed.merged_into_id == target.id

      assert repo().get!(Reply, reply.id).ticket_id == target.id
      assert repo().get!(Reply, note.id).ticket_id == target.id
      assert repo().get!(Attachment, attachment.id).ticket_id == target.id

      [target_note] = system_notes(target)
      assert target_note.body == "Ticket #{source.reference} was merged into this ticket."
      assert target_note.is_internal

      [source_note] = system_notes(source)
      assert source_note.body == "This ticket was merged into #{target.reference}."

      events = repo().all(from(d in WebhookDelivery, select: d.event))
      assert "ticket.status_changed" in events
      assert "ticket.closed" in events
    end

    test "a ticket cannot be merged into itself, or merged twice" do
      source = ticket!("One")
      target = ticket!("Two")

      conn =
        visit(:post, "/support/admin/tickets/#{source.reference}/merge", @admin, %{
          "target_reference" => source.reference
        })

      assert conn.status == 302
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "itself"
      assert repo().get!(Ticket, source.id).merged_into_id == nil

      assert {:ok, _} = TicketMergeService.merge(source, target)
      other = ticket!("Three")

      assert {:error, :already_merged} =
               TicketMergeService.merge(repo().get!(Ticket, source.id), other)
    end

    test "an unknown or merged target is a 404" do
      source = ticket!("One")
      merged = ticket!("Merged")
      {:ok, _} = TicketMergeService.merge(merged, ticket!("Kept"))

      for target_reference <- ["NOPE-1", merged.reference, ""] do
        conn =
          visit(:post, "/support/admin/tickets/#{source.reference}/merge", @admin, %{
            "target_reference" => target_reference
          })

        assert conn.status == 404
      end

      assert repo().get!(Ticket, source.id).status == "open"
    end

    test "search finds unmerged tickets by subject or reference, wildcards literal" do
      a = ticket!("Refund for order 100%")
      b = ticket!("Refund request")
      merged = ticket!("Refund merged away")
      {:ok, _} = TicketMergeService.merge(merged, b)

      found = search("refund")
      assert Enum.sort(Enum.map(found, & &1["id"])) == Enum.sort([a.id, b.id])

      assert [
               %{"id" => _, "reference" => _, "subject" => _, "status" => _, "created_at" => _}
               | _
             ] =
               found

      assert Enum.map(search("100%"), & &1["id"]) == [a.id]
      assert search("_efund") == []
      assert Enum.map(search(String.downcase(b.reference)), & &1["id"]) == [b.id]
    end

    test "agents cannot merge or search" do
      source = ticket!("One")
      target = ticket!("Two")

      conn =
        visit(:post, "/support/admin/tickets/#{source.reference}/merge", @agent, %{
          "target_reference" => target.reference
        })

      assert conn.status in [401, 403]
      assert visit(:get, "/support/admin/tickets/merge-search?q=One", @agent).status in [401, 403]
      assert repo().get!(Ticket, source.id).merged_into_id == nil
    end
  end

  describe "bulk actions" do
    test "an admin changes status, priority, assignee, tags and department in bulk" do
      tickets = [ticket!("A"), ticket!("B")]
      ids = Enum.map(tickets, & &1.id)
      tag = %Tag{} |> Tag.changeset(%{name: "vip"}) |> repo().insert!()
      dept = %Department{} |> Department.changeset(%{name: "Billing"}) |> repo().insert!()

      for {action, value} <- [
            {"status", "resolved"},
            {"priority", "urgent"},
            {"assign", 77},
            {"tags", [tag.id]},
            {"department", dept.id}
          ] do
        conn = bulk("/support/admin/tickets/bulk", @admin, ids, action, value)
        assert conn.status == 302
        assert Phoenix.Flash.get(conn.assigns.flash, :info) == "2 tickets updated."
      end

      for ticket <- repo().all(from(t in Ticket, where: t.id in ^ids, preload: :tags)) do
        assert ticket.status == "resolved"
        assert ticket.priority == "urgent"
        assert ticket.assigned_to == 77
        assert Enum.map(ticket.tags, & &1.id) == [tag.id]
        assert ticket.department_id == dept.id
      end
    end

    test "an agent can bulk-update but not delete; an admin can delete" do
      tickets = [ticket!("A"), ticket!("B")]
      ids = Enum.map(tickets, & &1.id)

      conn = bulk("/support/agent/tickets/bulk", @agent, ids, "priority", "high")
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/support/agent/tickets"]
      assert Enum.all?(repo().all(Ticket), &(&1.priority == "high"))

      assert bulk("/support/agent/tickets/bulk", @agent, ids, "delete", nil).status == 403
      assert repo().aggregate(Ticket, :count) == 2

      assert bulk("/support/admin/tickets/bulk", @admin, ids, "delete", nil).status == 302
      assert repo().aggregate(Ticket, :count) == 0
    end

    test "invalid bodies are refused, and a bad value skips the ticket" do
      [a] = [ticket!("A")]

      assert bulk("/support/admin/tickets/bulk", @admin, [], "status", "closed").status == 422
      assert bulk("/support/admin/tickets/bulk", @admin, [a.id], "explode", "x").status == 422
      assert bulk("/support/admin/tickets/bulk", @admin, [a.id], "status", nil).status == 422

      conn = bulk("/support/admin/tickets/bulk", @admin, [a.id], "status", "nonsense")
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "0 tickets updated."
      assert repo().get!(Ticket, a.id).status == "open"
    end
  end

  defp ticket!(subject) do
    {:ok, ticket} = TicketService.create(%{subject: subject, description: "x"})
    ticket
  end

  defp system_notes(ticket) do
    repo().all(from(r in Reply, where: r.ticket_id == ^ticket.id and r.is_system == true))
  end

  defp subscribe(events) do
    {:ok, _} =
      Webhooks.create(repo(), %{url: "https://example.test/hook", events: events, active: true})
  end

  defp search(term) do
    conn =
      visit(:get, "/support/admin/tickets/merge-search?q=#{URI.encode_www_form(term)}", @admin)

    assert conn.status == 200
    Jason.decode!(conn.resp_body)["tickets"]
  end

  defp bulk(path, user, ids, action, value) do
    visit(:post, path, user, %{"ticket_ids" => ids, "action" => action, "value" => value})
  end

  defp visit(method, path, user, body \\ nil) do
    base =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    base
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> put_req_header("accept", "application/json")
    |> Router.call(Router.init([]))
  end
end
