defmodule Escalated.Controllers.MobileGuestApiTest do
  @moduledoc """
  The mobile guest API (`{prefix}/api/v1/mobile/guest/*`), through the host
  router, against the shared contract in escalated-developer-context
  (`domain-model/mobile-guest-api.md`): the same codes, grants and guest
  budgets as the browser and widget guest routes.
  """
  use Escalated.PageCase

  import Ecto.Query

  alias Escalated.RateLimiter
  alias Escalated.Schemas.{Contact, Department, GuestGrant, Reply, Ticket}
  alias Escalated.Services.{ChatSessionService, TicketService}
  alias Escalated.Test.GuestAccessHelpers, as: Helpers
  alias Escalated.Test.Router

  @base "/support/api/v1/mobile/guest"

  defmodule Limiter do
    @moduledoc false
    def check(bucket, key, max_requests, window_ms) do
      server = Application.fetch_env!(:escalated, :mobile_guest_rate_limit_server)
      RateLimiter.check(bucket, key, max_requests, window_ms, server)
    end
  end

  # A limiter of its own with a frozen clock, so the tests neither share the
  # node-wide budget nor straddle a window.
  setup do
    Helpers.configure()
    server = start_supervised!({RateLimiter, name: nil, clock: fn -> 0 end})
    put_envs(rate_limit_backend: Limiter, mobile_guest_rate_limit_server: server)
    :ok
  end

  defp put_envs(settings) do
    previous =
      Enum.map(settings, fn {key, _} -> {key, Application.fetch_env(:escalated, key)} end)

    Enum.each(settings, fn {key, value} -> Application.put_env(:escalated, key, value) end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)
  end

  defp request(method, path, body \\ nil, opts \\ []) do
    router = Keyword.get(opts, :router, Router)

    conn =
      if body,
        do:
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json"),
        else: conn(method, path)

    conn =
      Enum.reduce(Keyword.get(opts, :headers, []), conn, fn {k, v}, c ->
        put_req_header(c, k, v)
      end)

    %{conn | remote_ip: Keyword.get(opts, :ip, {127, 0, 0, 1})}
    |> init_test_session(%{})
    |> router.call(router.init([]))
  end

  defp body(conn), do: Jason.decode!(conn.resp_body)

  # POST /verification, then read the emailed code.
  defp verify(address, purpose \\ "ticket") do
    conn = request(:post, @base <> "/verification", %{"email" => address, "purpose" => purpose})
    assert conn.status == 202
    %{"verification_id" => id, "expires_in" => 600} = body(conn)
    canonical = String.downcase(String.trim(address))

    receive do
      {:guest_code, ^canonical, code, ^purpose} -> {id, code}
    after
      1000 -> flunk("no code was delivered")
    end
  end

  defp payload(address, {id, code}, extra \\ %{}) do
    Map.merge(
      %{
        "name" => "Gus",
        "email" => address,
        "subject" => "Where is my parcel",
        "description" => "It is late",
        "verification_id" => id,
        "verification_code" => code
      },
      extra
    )
  end

  defp create!(address \\ "guest@example.test", extra \\ %{}) do
    conn = request(:post, @base <> "/tickets", payload(address, verify(address), extra))
    assert conn.status == 201, conn.resp_body
    body(conn)["data"]
  end

  defp assert_private(conn) do
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
  end

  describe "POST /guest/tickets" do
    test "without proof is 422 and creates no contact or ticket" do
      conn = request(:post, @base <> "/tickets", payload("guest@example.test", {nil, nil}))
      assert conn.status == 422
      assert_private(conn)
      assert body(conn)["errors"]["verification_id"]

      wrong = payload("guest@example.test", {Ecto.UUID.generate(), "12345678"})
      conn = request(:post, @base <> "/tickets", wrong)
      assert conn.status == 422
      assert body(conn)["errors"]["verification_code"]

      assert Escalated.repo().aggregate(Ticket, :count) == 0
      assert Escalated.repo().aggregate(Contact, :count) == 0
    end

    test "field validation runs before the proof" do
      proof = verify("guest@example.test")

      conn =
        request(
          :post,
          @base <> "/tickets",
          payload("guest@example.test", proof, %{"subject" => "", "priority" => "whenever"})
        )

      assert conn.status == 422
      assert %{"subject" => _, "priority" => _} = body(conn)["errors"]
      refute Map.has_key?(body(conn)["errors"], "verification_code")
      assert Escalated.repo().aggregate(Ticket, :count) == 0

      # The code was not spent by the refused request.
      conn = request(:post, @base <> "/tickets", payload("guest@example.test", proof))
      assert conn.status == 201
    end

    test "verification then create is 201 with a grant; reusing the code is 422" do
      department =
        Escalated.repo().insert!(Department.changeset(%Department{}, %{name: "Billing"}))

      proof = verify("Guest@Example.test ")

      conn =
        request(
          :post,
          @base <> "/tickets",
          payload("Guest@Example.test ", proof, %{
            "priority" => "high",
            "department_id" => department.id,
            "status" => "closed",
            "assigned_to" => 1,
            "metadata" => %{"vip" => true},
            "external_reference" => "X-1"
          })
        )

      assert conn.status == 201
      assert_private(conn)
      %{"data" => data, "message" => "Ticket created."} = body(conn)

      assert is_binary(data["guest_access_token"])
      assert is_binary(data["guest_access_expires_at"])
      assert data["status"] == %{"value" => "open", "label" => "Open"}
      assert data["priority"] == %{"value" => "high", "label" => "High"}
      assert data["channel"] == "web"
      assert data["metadata"] == %{}
      assert data["requester"] == %{"name" => "Gus", "email" => "guest@example.test"}
      assert data["assignee"] == nil
      assert data["department"] == %{"id" => department.id, "name" => "Billing"}
      assert data["replies"] == []
      assert data["tags"] == []
      assert data["activities"] == []
      assert data["is_following"] == false
      assert data["followers_count"] == 0

      assert Map.keys(data["sla"]) |> Enum.sort() ==
               ~w(first_response_at first_response_breached first_response_due_at resolution_breached resolution_due_at)

      refute Map.has_key?(data, "external_reference")
      refute Map.has_key?(data, "chat_metadata")

      ticket = Escalated.repo().get!(Ticket, data["id"])
      assert ticket.reference == data["reference"]
      assert ticket.guest_email == "guest@example.test"
      assert ticket.status == "open"
      assert ticket.assigned_to == nil
      assert ticket.metadata == %{}
      assert ticket.channel == "web"
      assert ticket.contact_id

      # The same code with a different request is refused.
      conn =
        request(
          :post,
          @base <> "/tickets",
          payload("guest@example.test", proof, %{"subject" => "Another"})
        )

      assert conn.status == 422
      assert body(conn)["errors"]["verification_code"]
      assert Escalated.repo().aggregate(Ticket, :count) == 1
    end

    test "the code is bound to its purpose" do
      proof = verify("guest@example.test", "lookup")
      conn = request(:post, @base <> "/tickets", payload("guest@example.test", proof))
      assert conn.status == 422
      assert body(conn)["errors"]["verification_code"]
    end

    test "is 403 while guest tickets are off" do
      put_envs(guest_tickets_enabled: false)

      conn = request(:post, @base <> "/tickets", payload("guest@example.test", {nil, nil}))
      assert conn.status == 403
      assert body(conn) == %{"message" => "Guest tickets are not enabled."}
      assert_private(conn)

      conn =
        request(:post, @base <> "/verification", %{
          "email" => "guest@example.test",
          "purpose" => "ticket"
        })

      assert conn.status == 403

      conn =
        request(:post, @base <> "/lookup", %{
          "email" => "guest@example.test",
          "reference" => "ESC-1",
          "verification_id" => Ecto.UUID.generate(),
          "verification_code" => "1"
        })

      assert conn.status == 403
    end
  end

  describe "the grant" do
    test "opens the mobile, browser and widget guest routes" do
      data = create!()
      token = data["guest_access_token"]

      conn = request(:get, @base <> "/tickets/" <> token)
      assert conn.status == 200
      assert_private(conn)
      assert body(conn)["data"]["guest_access_token"] == token
      assert body(conn)["data"]["subject"] == "Where is my parcel"

      page = visit(:get, "/support/guest/" <> token, nil) |> page!("Escalated/Guest/Show")
      assert page["ticket"]["reference"] == data["reference"]

      widget =
        request(:get, "/support/widget/tickets/" <> data["reference"], nil,
          headers: [{"authorization", "Bearer " <> token}]
        )

      assert widget.status == 200
    end

    test "from a widget create opens the mobile routes" do
      address = "widget@example.test"
      {id, code} = verify(address)

      conn =
        request(:post, "/support/widget/tickets", %{
          "name" => "W",
          "email" => address,
          "subject" => "From the widget",
          "description" => "Hello",
          "verification_id" => id,
          "verification_code" => code
        })

      assert conn.status == 201
      token = body(conn)["guest_access_token"]

      conn = request(:get, @base <> "/tickets/" <> token)
      assert conn.status == 200
      assert body(conn)["data"]["subject"] == "From the widget"
    end

    test "an expired, malformed, over-long or chat grant is 404" do
      data = create!()
      token = data["guest_access_token"]

      for bad <- ["nope", String.duplicate("a", 5000)] do
        conn = request(:get, @base <> "/tickets/" <> bad)
        assert conn.status == 404
        assert_private(conn)
      end

      past = DateTime.add(DateTime.utc_now(), -60) |> DateTime.truncate(:second)

      Escalated.repo().update_all(from(g in GuestGrant, where: g.ticket_id == ^data["id"]),
        set: [expires_at: past]
      )

      assert request(:get, @base <> "/tickets/" <> token).status == 404

      assert request(:post, @base <> "/tickets/#{token}/replies", %{
               "email" => "guest@example.test",
               "body" => "Hi"
             }).status == 404

      {:ok, _ticket, _session, result} =
        ChatSessionService.start_guest(Helpers.proof("chatter@example.test", "chat"), %{
          guest_name: "Chat",
          guest_email: "chatter@example.test",
          subject: "Hi",
          message: "Hello",
          visitor_ip: "127.0.0.1"
        })

      assert request(:get, @base <> "/tickets/" <> result["guest_access_token"]).status == 404
    end

    test "lookup issues fresh grants that open the mobile routes" do
      data = create!()
      {id, code} = verify("guest@example.test", "lookup")

      conn =
        request(:post, @base <> "/lookup", %{
          "email" => "GUEST@example.test",
          "reference" => data["reference"],
          "verification_id" => id,
          "verification_code" => code
        })

      assert conn.status == 200
      assert_private(conn)
      assert [%{"reference" => ref, "guest_access_token" => fresh} = row] = body(conn)["data"]
      assert ref == data["reference"]
      assert Map.keys(row) |> Enum.sort() == ~w(expires_at guest_access_token reference subject)
      assert request(:get, @base <> "/tickets/" <> fresh).status == 200
      # Issuing a grant rotates it: the earlier link stops working.
      assert request(:get, @base <> "/tickets/" <> data["guest_access_token"]).status == 404

      conn =
        request(:post, @base <> "/lookup", %{
          "email" => "guest@example.test",
          "reference" => data["reference"],
          "verification_id" => id,
          "verification_code" => "00000000"
        })

      assert conn.status == 422
      assert body(conn)["errors"]["verification_code"]
    end
  end

  describe "POST /guest/tickets/:token/replies" do
    test "accepts a differently-cased email, refuses a mismatch and a closed ticket" do
      data = create!()
      path = @base <> "/tickets/#{data["guest_access_token"]}/replies"

      conn = request(:post, path, %{"email" => " GUEST@Example.TEST", "body" => "Thank you"})
      assert conn.status == 201
      assert_private(conn)
      assert body(conn) == %{"message" => "Reply sent."}

      reply = Escalated.repo().one!(from(r in Reply, where: r.ticket_id == ^data["id"]))
      assert reply.body == "Thank you"
      assert reply.author_id == nil
      refute reply.is_internal

      conn = request(:post, path, %{"email" => "someone@example.test", "body" => "Hi"})
      assert conn.status == 403
      assert body(conn) == %{"message" => "The provided email does not match this ticket."}

      conn = request(:post, path, %{"email" => "guest@example.test", "body" => ""})
      assert conn.status == 422
      assert body(conn)["errors"]["body"]

      Escalated.repo().update_all(from(t in Ticket, where: t.id == ^data["id"]),
        set: [status: "closed"]
      )

      conn = request(:post, path, %{"email" => "guest@example.test", "body" => "Hello?"})
      assert conn.status == 422
      assert body(conn) == %{"message" => "This ticket is closed."}
      assert Escalated.repo().aggregate(Reply, :count) == 1
    end
  end

  describe "GET /guest/tickets/:token" do
    test "shows public replies newest first and never internal notes" do
      data = create!()
      ticket = Escalated.repo().get!(Ticket, data["id"])
      path = @base <> "/tickets/#{data["guest_access_token"]}"

      assert request(:post, path <> "/replies", %{
               "email" => "guest@example.test",
               "body" => "First"
             }).status == 201

      agent = host_user!(%{name: "Agent Smith", email: "smith@example.test"})

      {:ok, _} =
        TicketService.reply(ticket, %{body: "Secret note", is_internal: true, author_id: agent.id})

      {:ok, _} =
        TicketService.reply(ticket, %{body: "From staff", is_internal: false, author_id: 42})

      {:ok, _} =
        TicketService.reply(ticket, %{body: "Named", is_internal: false, author_id: agent.id})

      Escalated.repo().update_all(from(t in Ticket, where: t.id == ^ticket.id),
        set: [assigned_to: agent.id]
      )

      conn = request(:get, path)
      assert conn.status == 200

      assert body(conn)["data"]["assignee"] == %{
               "id" => 0,
               "name" => "Agent Smith",
               "email" => ""
             }

      replies = body(conn)["data"]["replies"]
      refute conn.resp_body =~ "Secret note"
      refute conn.resp_body =~ "smith@example.test"

      assert [
               %{"body" => "Named"} = named,
               %{"body" => "From staff"} = staff,
               %{"body" => "First"} = guest
             ] =
               replies

      assert named["author"] == %{"id" => 0, "name" => "Agent Smith", "email" => ""}
      assert staff["author"] == %{"id" => 0, "name" => "Support", "email" => ""}
      assert guest["author"] == %{"id" => 0, "name" => "Gus", "email" => "guest@example.test"}
      assert staff["is_internal_note"] == false
      assert staff["attachments"] == []

      assert Map.keys(staff) |> Enum.sort() ==
               ~w(attachments author body created_at id is_internal_note is_pinned)
    end
  end

  describe "rate limits" do
    test "the submission budget answers 429 with Retry-After, shared with the widget" do
      put_envs(guest_submission_rate_limit: %{tickets_per_minute: 3})

      for n <- 1..2 do
        conn =
          request(:post, @base <> "/verification", %{
            "email" => "g#{n}@example.test",
            "purpose" => "ticket"
          })

        assert conn.status == 202
      end

      # The widget's ticket create spends the same per-IP budget.
      assert request(:post, "/support/widget/tickets", %{"email" => "x@example.test"}).status ==
               422

      conn =
        request(:post, @base <> "/verification", %{
          "email" => "g9@example.test",
          "purpose" => "ticket"
        })

      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
      assert_private(conn)
    end

    test "the reply budget covers lookup and replies" do
      put_envs(guest_submission_rate_limit: %{replies_per_minute: 1})

      lookup = %{
        "email" => "guest@example.test",
        "reference" => "ESC-1",
        "verification_id" => Ecto.UUID.generate(),
        "verification_code" => "1"
      }

      assert request(:post, @base <> "/lookup", lookup).status == 422

      conn =
        request(:post, @base <> "/tickets/whatever/replies", %{
          "email" => "guest@example.test",
          "body" => "Hi"
        })

      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
    end

    test "the request budget covers every mobile guest route" do
      put_envs(guest_rate_limit: %{max_requests: 1, window_ms: 60_000})

      assert request(:get, @base <> "/tickets/nope").status == 404
      conn = request(:get, @base <> "/tickets/nope")
      assert conn.status == 429
      assert get_resp_header(conn, "retry-after") != []
    end
  end

  test "the routes do not exist while the REST API is disabled" do
    for {method, path} <- [
          {:post, @base <> "/verification"},
          {:post, @base <> "/lookup"},
          {:post, @base <> "/tickets"},
          {:get, @base <> "/tickets/abc"},
          {:post, @base <> "/tickets/abc/replies"}
        ] do
      assert_raise Phoenix.Router.NoRouteError, fn ->
        request(method, path, %{}, router: Escalated.Test.WidgetEmbedRouter)
      end
    end
  end
end
