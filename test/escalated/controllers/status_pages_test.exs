defmodule Escalated.Controllers.StatusPagesTest do
  @moduledoc """
  `Escalated/Admin/Statuses/{Index,Form}` against the props the shared Vue
  pages read and the routes they post to (escalated-laravel's
  `Admin\\StatusController`), plus the system rows for the built-in statuses.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{Ticket, TicketStatus}
  alias Escalated.Services.TicketService

  defp repo, do: Escalated.repo()

  @status_keys ~w(id label slug category color description position is_default is_system
                  created_at updated_at)
  @categories ["new", "open", "pending", "on_hold", "solved"]

  setup do
    %{
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      agent: host_user!(%{name: "Al Agent", is_agent: true})
    }
  end

  defp status!(attrs) do
    %TicketStatus{}
    |> TicketStatus.changeset(
      Map.merge(%{label: "Awaiting parts", slug: "awaiting_parts", category: "on_hold"}, attrs)
    )
    |> repo().insert!()
  end

  defp custom_count,
    do: repo().aggregate(from(s in TicketStatus, where: s.is_system == false), :count)

  defp body(overrides \\ %{}) do
    Map.merge(
      %{
        "label" => "Awaiting Parts",
        "category" => "on_hold",
        "color" => "#f59e0b",
        "description" => "Waiting for a supplier",
        "position" => 3,
        "is_default" => false
      },
      overrides
    )
  end

  defp errors(conn) do
    assert conn.status in [302, 303, 422], "expected a validation answer, got #{conn.status}"

    conn |> raw_errors() |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp raw_errors(conn) do
    case conn.status do
      422 ->
        Jason.decode!(conn.resp_body)["errors"]

      _ ->
        conn |> Plug.Conn.fetch_session() |> Plug.Conn.get_session("inertia_errors") || %{}
    end
  end

  defp system!(slug), do: repo().get_by!(TicketStatus, slug: slug, is_system: true)

  describe "Escalated/Admin/Statuses/Index" do
    test "lists every status by category then position with Laravel's keys", %{admin: admin} do
      later = status!(%{label: "Later", slug: "later", category: "on_hold", position: 9})
      first = status!(%{label: "First", slug: "first", category: "new", position: 0})

      props =
        visit(:get, "/support/admin/statuses", admin)
        |> page!("Escalated/Admin/Statuses/Index")

      assert props["categories"] == @categories

      for row <- props["statuses"], do: assert_keys(row, @status_keys, "status")

      ids = Enum.map(props["statuses"], & &1["id"])
      assert first.id in ids and later.id in ids

      order =
        Enum.map(props["statuses"], fn s ->
          {Enum.find_index(@categories, &(&1 == s["category"])), s["position"]}
        end)

      assert order == Enum.sort(order)

      row = Enum.find(props["statuses"], &(&1["id"] == later.id))
      assert row["label"] == "Later"
      assert row["slug"] == "later"
      assert row["is_system"] == false
    end

    test "carries one system row per built-in status, in its category", %{admin: admin} do
      props =
        visit(:get, "/support/admin/statuses", admin)
        |> page!("Escalated/Admin/Statuses/Index")

      system = for s <- props["statuses"], s["is_system"], into: %{}, do: {s["slug"], s}
      assert Map.keys(system) |> Enum.sort() == Enum.sort(Ticket.statuses())
      assert system["waiting_on_customer"]["category"] == "pending"
      assert system["snoozed"]["category"] == "on_hold"
      assert system["resolved"]["category"] == "solved"
      assert system["closed"]["category"] == "solved"
      assert system["live"]["category"] == "open"
      assert system["open"]["category"] == "open"
      assert system["waiting_on_customer"]["label"] == "Waiting on Customer"
    end

    test "is admin only", %{agent: agent} do
      assert visit(:get, "/support/admin/statuses", agent).status == 403
    end
  end

  describe "Escalated/Admin/Statuses/Form" do
    test "create sends the categories", %{admin: admin} do
      props =
        visit(:get, "/support/admin/statuses/create", admin)
        |> page!("Escalated/Admin/Statuses/Form")

      assert props["categories"] == @categories
      refute Map.has_key?(props, "status")
    end

    test "edit sends the status and the categories", %{admin: admin} do
      status = status!(%{description: "Parts on order"})

      props =
        visit(:get, "/support/admin/statuses/#{status.id}/edit", admin)
        |> page!("Escalated/Admin/Statuses/Form")

      assert_keys(props, ~w(status categories))
      assert_keys(props["status"], @status_keys, "status")
      assert props["status"]["id"] == status.id
      assert props["status"]["description"] == "Parts on order"
      assert props["categories"] == @categories
    end

    test "edit of an unknown status is a 404", %{admin: admin} do
      assert visit(:get, "/support/admin/statuses/999999/edit", admin).status == 404
    end
  end

  describe "status writes" do
    test "store creates the status and generates an underscore slug", %{admin: admin} do
      conn = visit(:post, "/support/admin/statuses", admin, body())

      assert conn.status in [302, 303]
      assert location(conn) == "/support/admin/statuses"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Status created."

      status = repo().get_by!(TicketStatus, slug: "awaiting_parts")
      assert status.label == "Awaiting Parts"
      assert status.category == "on_hold"
      assert status.color == "#f59e0b"
      assert status.description == "Waiting for a supplier"
      assert status.position == 3
      refute status.is_default
      refute status.is_system
    end

    test "store de-duplicates the slug with _2, _3", %{admin: admin} do
      for _ <- 1..3, do: visit(:post, "/support/admin/statuses", admin, body())

      slugs =
        repo().all(
          from(s in TicketStatus, where: s.is_system == false, order_by: s.id, select: s.slug)
        )

      assert slugs == ["awaiting_parts", "awaiting_parts_2", "awaiting_parts_3"]
    end

    test "a label equal to a built-in status gets a fresh slug", %{admin: admin} do
      visit(:post, "/support/admin/statuses", admin, body(%{"label" => "Resolved"}))

      assert repo().get_by!(TicketStatus, is_system: false).slug == "resolved_2"
    end

    test "store validates label, category, color, position and is_default", %{admin: admin} do
      errors =
        visit(
          :post,
          "/support/admin/statuses",
          admin,
          body(%{
            "label" => "",
            "category" => "closed",
            "color" => String.duplicate("x", 21),
            "position" => "first",
            "is_default" => "maybe"
          })
        )
        |> errors()

      for key <- ~w(label category color position is_default),
          do: assert(Map.has_key?(errors, key), "no error for #{key}: #{inspect(errors)}")

      assert custom_count() == 0
    end

    test "store requires a colour", %{admin: admin} do
      errors =
        visit(:post, "/support/admin/statuses", admin, Map.delete(body(), "color")) |> errors()

      assert Map.has_key?(errors, "color")
    end

    test "is_default is exclusive within a category", %{admin: admin} do
      old = status!(%{label: "Old default", slug: "old_default", is_default: true})
      other = status!(%{label: "Other", slug: "other", category: "open", is_default: true})

      visit(:post, "/support/admin/statuses", admin, body(%{"is_default" => true}))

      assert repo().get_by!(TicketStatus, slug: "awaiting_parts").is_default
      refute repo().get!(TicketStatus, old.id).is_default
      assert repo().get!(TicketStatus, other.id).is_default

      conn =
        visit(
          :put,
          "/support/admin/statuses/#{old.id}",
          admin,
          body(%{"label" => "Old default", "is_default" => true})
        )

      assert conn.status in [302, 303]
      assert repo().get!(TicketStatus, old.id).is_default
      refute repo().get_by!(TicketStatus, slug: "awaiting_parts").is_default
    end

    test "update changes the status and keeps its slug", %{admin: admin} do
      status = status!(%{})

      conn =
        visit(
          :put,
          "/support/admin/statuses/#{status.id}",
          admin,
          body(%{"label" => "Parts ordered", "category" => "pending", "color" => "#000000"})
        )

      assert conn.status in [302, 303]
      assert location(conn) == "/support/admin/statuses"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Status updated."

      updated = repo().get!(TicketStatus, status.id)
      assert updated.label == "Parts ordered"
      assert updated.category == "pending"
      assert updated.color == "#000000"
      assert updated.slug == "awaiting_parts"
    end

    test "update validates", %{admin: admin} do
      status = status!(%{})

      errors =
        visit(:put, "/support/admin/statuses/#{status.id}", admin, body(%{"label" => ""}))
        |> errors()

      assert Map.has_key?(errors, "label")
      assert repo().get!(TicketStatus, status.id).label == "Awaiting parts"
    end

    test "a system status keeps its slug and category but takes the rest", %{admin: admin} do
      resolved = system!("resolved")

      conn =
        visit(
          :put,
          "/support/admin/statuses/#{resolved.id}",
          admin,
          body(%{"label" => "Done", "category" => "open", "color" => "#123456"})
        )

      errors = errors(conn)
      assert Map.has_key?(errors, "category")

      unchanged = repo().get!(TicketStatus, resolved.id)
      assert unchanged.category == "solved"
      assert unchanged.label == "Resolved"

      conn =
        visit(
          :put,
          "/support/admin/statuses/#{resolved.id}",
          admin,
          body(%{"label" => "Done", "category" => "solved", "color" => "#123456"})
        )

      assert conn.status in [302, 303]
      updated = repo().get!(TicketStatus, resolved.id)
      assert updated.label == "Done"
      assert updated.color == "#123456"
      assert updated.slug == "resolved"
      assert updated.category == "solved"
      assert updated.is_system
    end

    test "a system status cannot be deleted", %{admin: admin} do
      open = system!("open")

      errors = visit(:delete, "/support/admin/statuses/#{open.id}", admin) |> errors()

      assert errors != %{}
      assert repo().get(TicketStatus, open.id)
    end

    test "destroy deletes a custom status and clears it from tickets", %{admin: admin} do
      status = status!(%{category: "solved", label: "Fixed", slug: "fixed"})
      {:ok, ticket} = TicketService.create(%{subject: "Printer", description: "Jammed"})
      {:ok, ticket} = TicketService.transition_status(ticket, "fixed")
      assert ticket.ticket_status_id == status.id

      conn = visit(:delete, "/support/admin/statuses/#{status.id}", admin)

      assert conn.status in [302, 303]
      assert location(conn) == "/support/admin/statuses"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Status deleted."
      refute repo().get(TicketStatus, status.id)

      reloaded = repo().get!(Ticket, ticket.id)
      assert reloaded.ticket_status_id == nil
      assert reloaded.status == "resolved"
    end

    test "writes are admin only", %{agent: agent} do
      assert visit(:post, "/support/admin/statuses", agent, body()).status == 403
      status = status!(%{})
      assert visit(:delete, "/support/admin/statuses/#{status.id}", agent).status == 403
      assert custom_count() == 1
    end
  end
end
