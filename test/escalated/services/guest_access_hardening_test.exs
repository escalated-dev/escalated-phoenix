defmodule Escalated.Services.GuestAccessHardeningTest do
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.RateLimiter
  alias Escalated.Schemas.{GuestChallenge, GuestGrant, SatisfactionRating, Ticket}
  alias Escalated.Services.{ChatSessionService, GuestAccess, TicketService}
  alias Escalated.Test.GuestAccessHelpers, as: Helpers
  alias Escalated.Test.Router

  defmodule TestBackend do
    @moduledoc false
    def check(bucket, key, max_requests, window_ms) do
      server = Application.fetch_env!(:escalated, :hardening_rate_limit_server)
      RateLimiter.check(bucket, key, max_requests, window_ms, server)
    end
  end

  setup do
    Helpers.configure()
    :ok
  end

  defp attrs,
    do: %{
      subject: "Parcel",
      description: "Please help",
      guest_name: "Recipient",
      guest_email: "recipient@example.test"
    }

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

  # A fresh node-local limiter with a frozen clock, so every request in a test
  # lands in the same window.
  defp isolated_rate_limiter(settings \\ []) do
    server = start_supervised!({RateLimiter, name: nil, clock: fn -> 0 end})
    put_envs([rate_limit_backend: TestBackend, hardening_rate_limit_server: server] ++ settings)
  end

  defp request(method, path, body \\ nil, headers \\ [], ip \\ {127, 0, 0, 1}) do
    conn =
      if body,
        do:
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json"),
        else: conn(method, path)

    conn =
      Enum.reduce(headers, %{conn | remote_ip: ip}, fn {k, v}, c -> put_req_header(c, k, v) end)

    conn |> init_test_session(%{}) |> Router.call(Router.init([]))
  end

  defp start_chat(address \\ "chatter@example.test") do
    {:ok, ticket, session, result} =
      ChatSessionService.start_guest(Helpers.proof(address, "chat"), %{
        guest_name: "Chat",
        guest_email: address,
        subject: "Hi",
        message: "Hello",
        visitor_ip: "127.0.0.1"
      })

    {ticket, session, result["guest_access_token"]}
  end

  # Every string anywhere in a stored value.
  defp strings(value) when is_binary(value), do: [value]

  defp strings(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> strings(k) ++ strings(v) end)

  defp strings(value) when is_list(value), do: Enum.flat_map(value, &strings/1)
  defp strings(_), do: []

  defp refute_capability_stored(challenge_id, purpose) do
    row = Escalated.repo().get!(GuestChallenge, challenge_id)
    refute is_nil(row.used_at)

    for value <- strings(row.result) do
      assert {:error, :not_found} = GuestAccess.resolve(value, purpose)
    end

    refute Map.has_key?(row.result, "guest_access_token")
  end

  describe "identical retries (replay)" do
    test "more than five identical retries all replay without spending attempts" do
      proof = Helpers.proof()
      assert {:ok, ticket, first} = TicketService.create_guest(proof, attrs())
      spent = Escalated.repo().get!(GuestChallenge, proof["verification_id"]).attempts

      for _ <- 1..7 do
        assert {:ok, same, replayed} = TicketService.create_guest(proof, attrs())
        assert same.id == ticket.id
        assert replayed["_replayed"] == true
        assert replayed["reference"] == ticket.reference
        assert replayed["expires_at"] == first["expires_at"]
        # An equivalent capability for the same grant, not a renewal.
        assert {:ok, %{id: id}, grant} = GuestAccess.resolve(replayed["guest_access_token"])
        assert id == ticket.id
        assert {:ok, _, ^grant} = GuestAccess.resolve(first["guest_access_token"])
      end

      assert Escalated.repo().get!(GuestChallenge, proof["verification_id"]).attempts == spent
      assert Escalated.repo().aggregate(Ticket, :count) == 1
      assert Escalated.repo().aggregate(GuestGrant, :count) == 1
    end

    test "wrong codes against a consumed proof are still charged and close it" do
      proof = Helpers.proof()
      assert {:ok, _, _} = TicketService.create_guest(proof, attrs())
      wrong = Map.put(proof, "verification_code", "wrong")

      for _ <- 1..5,
          do: assert({:error, :verification} = TicketService.create_guest(wrong, attrs()))

      assert Escalated.repo().get!(GuestChallenge, proof["verification_id"]).attempts == 5
      assert {:error, :verification} = TicketService.create_guest(proof, attrs())
    end

    test "a changed request with the right code is refused without a second ticket" do
      proof = Helpers.proof()
      assert {:ok, _, _} = TicketService.create_guest(proof, attrs())

      assert {:error, :verification} =
               TicketService.create_guest(proof, %{attrs() | subject: "Changed"})

      assert Escalated.repo().aggregate(Ticket, :count) == 1
    end

    test "a replay after renewal or revocation is refused" do
      proof = Helpers.proof()
      assert {:ok, ticket, _} = TicketService.create_guest(proof, attrs())
      assert {:ok, :ok} = GuestAccess.revoke(ticket)
      assert {:error, :verification} = TicketService.create_guest(proof, attrs())
    end
  end

  describe "stored proof results" do
    test "ticket creation stores no usable capability" do
      proof = Helpers.proof()
      assert {:ok, _, result} = TicketService.create_guest(proof, attrs())
      assert {:ok, _, _} = GuestAccess.resolve(result["guest_access_token"])
      refute_capability_stored(proof["verification_id"], "ticket")
    end

    test "chat start stores no usable capability and replays the same session" do
      proof = Helpers.proof("chatter@example.test", "chat")

      chat = %{
        guest_name: "Chat",
        guest_email: "chatter@example.test",
        message: "Hello"
      }

      assert {:ok, ticket, session, result} = ChatSessionService.start_guest(proof, chat)
      refute_capability_stored(proof["verification_id"], "chat")
      assert {:ok, _, same, replayed} = ChatSessionService.start_guest(proof, chat)
      assert same.id == session.id
      assert {:ok, %{id: id}, _} = GuestAccess.resolve(replayed["guest_access_token"], "chat")
      assert id == ticket.id
      assert {:ok, _, _} = GuestAccess.resolve(result["guest_access_token"], "chat")
    end

    test "lookup stores no usable capability and replays every renewed grant" do
      {:ok, ticket} = TicketService.insert(attrs())

      proof =
        Helpers.proof("recipient@example.test", "lookup")
        |> Map.put("reference", ticket.reference)

      assert {:ok, %{"data" => [first]}} = GuestAccess.lookup(proof)
      refute_capability_stored(proof["verification_id"], "ticket")
      assert {:ok, %{"data" => [again], "_replayed" => true}} = GuestAccess.lookup(proof)
      assert again["reference"] == ticket.reference
      assert {:ok, _, grant} = GuestAccess.resolve(again["guest_access_token"])
      assert {:ok, _, ^grant} = GuestAccess.resolve(first["guest_access_token"])
    end

    test "a stored raw capability from an earlier release is never replayed" do
      proof = Helpers.proof()
      assert {:ok, _, result} = TicketService.create_guest(proof, attrs())
      row = Escalated.repo().get!(GuestChallenge, proof["verification_id"])

      # A row written before the upgrade kept the raw token: it is never handed
      # back; the replay re-derives the capability from the current grant.
      Escalated.repo().update!(
        Ecto.Changeset.change(row, result: Map.put(row.result, "guest_access_token", "stale"))
      )

      assert {:ok, _, replayed} = TicketService.create_guest(proof, attrs())
      refute replayed["guest_access_token"] == "stale"
      assert {:ok, _, _} = GuestAccess.resolve(replayed["guest_access_token"])
      assert {:ok, _, _} = GuestAccess.resolve(result["guest_access_token"])
    end
  end

  describe "mailbox budget" do
    test "one address budget per network does not lock the owner out from elsewhere" do
      stranger = {203, 0, 113, 7}
      owner = {198, 51, 100, 20}

      for _ <- 1..3,
          do:
            assert(
              {:ok, _} = GuestAccess.challenge("victim@example.test", "lookup", ip: stranger)
            )

      assert {:error, :rate_limited} =
               GuestAccess.challenge("Victim@Example.test ", "chat", ip: stranger)

      assert {:ok, _} = GuestAccess.challenge("victim@example.test", "ticket", ip: owner)
    end

    test "a higher global cap per mailbox still stops delivery bombing across networks" do
      put_envs(guest_mailbox_ip_limit: 3, guest_mailbox_limit: 5)

      sent =
        for n <- 1..8 do
          GuestAccess.challenge("victim@example.test", "lookup", ip: {203, 0, 113, n})
        end

      assert Enum.count(sent, &match?({:ok, _}, &1)) == 5
      assert Enum.count(sent, &(&1 == {:error, :rate_limited})) == 3
    end

    test "a refused network does not spend the global budget" do
      put_envs(guest_mailbox_ip_limit: 1, guest_mailbox_limit: 2)
      stranger = {203, 0, 113, 7}
      assert {:ok, _} = GuestAccess.challenge("victim@example.test", "lookup", ip: stranger)

      for _ <- 1..5,
          do:
            assert(
              {:error, :rate_limited} =
                GuestAccess.challenge("victim@example.test", "lookup", ip: stranger)
            )

      assert {:ok, _} = GuestAccess.challenge("victim@example.test", "lookup", ip: {1, 2, 3, 4})
    end

    test "IPv6 addresses share a budget per /64" do
      put_envs(guest_mailbox_ip_limit: 1)
      a = {0x2001, 0xDB8, 1, 2, 0, 0, 0, 1}
      same_64 = {0x2001, 0xDB8, 1, 2, 0xFFFF, 1, 2, 3}
      other_64 = {0x2001, 0xDB8, 1, 3, 0, 0, 0, 1}
      assert {:ok, _} = GuestAccess.challenge("victim@example.test", "lookup", ip: a)

      assert {:error, :rate_limited} =
               GuestAccess.challenge("victim@example.test", "lookup", ip: same_64)

      assert {:ok, _} = GuestAccess.challenge("victim@example.test", "lookup", ip: other_64)
    end

    test "the verification endpoint charges the caller's network" do
      stranger = {203, 0, 113, 7}

      for _ <- 1..3 do
        assert request(
                 :post,
                 "/support/guest/verification",
                 %{email: "victim@example.test", purpose: "lookup"},
                 [],
                 stranger
               ).status == 202
      end

      assert request(
               :post,
               "/support/guest/verification",
               %{email: "victim@example.test", purpose: "lookup"},
               [],
               stranger
             ).status == 429

      assert request(
               :post,
               "/support/widget/verification",
               %{email: "victim@example.test", purpose: "lookup"},
               [],
               {198, 51, 100, 20}
             ).status == 202
    end
  end

  describe "rate limiter keys" do
    test "IPv6 clients are keyed by /64 and IPv4-mapped clients as IPv4" do
      assert RateLimiter.client_key({203, 0, 113, 7}) == {203, 0, 113, 7}

      assert RateLimiter.client_key({0x2001, 0xDB8, 1, 2, 3, 4, 5, 6}) ==
               RateLimiter.client_key({0x2001, 0xDB8, 1, 2, 9, 9, 9, 9})

      refute RateLimiter.client_key({0x2001, 0xDB8, 1, 2, 0, 0, 0, 1}) ==
               RateLimiter.client_key({0x2001, 0xDB8, 1, 3, 0, 0, 0, 1})

      assert RateLimiter.client_key({0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7107}) ==
               {203, 0, 113, 7}
    end

    test "public route limits share one budget across an IPv6 /64" do
      isolated_rate_limiter(guest_rate_limit: %{max_requests: 1, window_ms: 60_000})

      assert request(
               :get,
               "/support/api/v1/guest/tickets/missing",
               nil,
               [],
               {0x2001, 0xDB8, 1, 2, 0, 0, 0, 1}
             ).status ==
               404

      assert request(
               :get,
               "/support/api/v1/guest/tickets/missing",
               nil,
               [],
               {0x2001, 0xDB8, 1, 2, 7, 7, 7, 7}
             ).status ==
               429
    end
  end

  describe "guest chat polling" do
    test "the documented three-second polling fits the default limits with sends and typing" do
      isolated_rate_limiter(widget_rate_limit: %{max_requests: 20, window_ms: 60_000})
      {_ticket, _session, token} = start_chat()

      # One minute of the shared widget: a poll every 3 s, a typing ping every 3 s
      # while composing, and several messages, all in the same window.
      statuses =
        for n <- 1..20 do
          poll = request(:get, "/support/widget/chat/#{token}/messages").status
          typing = request(:post, "/support/widget/chat/#{token}/typing").status

          send =
            if rem(n, 4) == 0,
              do:
                request(:post, "/support/widget/chat/#{token}/messages", %{body: "msg #{n}"}).status,
              else: 201

          {poll, typing, send}
        end

      assert Enum.all?(statuses, &(&1 == {200, 200, 201}))
      # The rest of the widget keeps its own budget.
      assert request(:get, "/support/widget/config").status == 200
    end

    test "each chat capability is bounded" do
      isolated_rate_limiter(
        widget_chat_rate_limit: %{max_requests: 3, window_ms: 60_000, max_requests_per_ip: 100}
      )

      {_ticket, _session, token} = start_chat()

      for _ <- 1..3,
          do: assert(request(:get, "/support/widget/chat/#{token}/messages").status == 200)

      throttled = request(:post, "/support/widget/chat/#{token}/messages", %{body: "hi"})
      assert throttled.status == 429
      assert get_resp_header(throttled, "retry-after") != []
    end

    test "changing guessed chat tokens cannot reset the per-network budget" do
      isolated_rate_limiter(
        widget_chat_rate_limit: %{max_requests: 100, window_ms: 60_000, max_requests_per_ip: 3}
      )

      for n <- 1..3,
          do: assert(request(:get, "/support/widget/chat/guess-#{n}/messages").status == 404)

      assert request(:get, "/support/widget/chat/guess-4/messages").status == 429
      assert request(:post, "/support/widget/chat/guess-5/typing").status == 429
    end

    test "legacy reference chat sends use the chat budget keyed by the header capability" do
      isolated_rate_limiter(widget_rate_limit: %{max_requests: 1, window_ms: 60_000})
      {ticket, _session, token} = start_chat()

      for n <- 1..3 do
        assert request(
                 :post,
                 "/support/widget/chat/sessions/#{ticket.reference}/messages",
                 %{body: "msg #{n}"},
                 [{"x-guest-access-token", token}]
               ).status == 201
      end
    end
  end

  describe "disabled widget" do
    setup do
      {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())
      {_chat, _session, chat_token} = start_chat()
      put_envs(widget_settings: %{enabled: false})
      %{ticket: ticket, token: result["guest_access_token"], chat_token: chat_token}
    end

    test "sends no codes and serves no lookups", %{ticket: ticket} do
      resp =
        request(:post, "/support/widget/verification", %{
          email: "recipient@example.test",
          purpose: "lookup"
        })

      assert resp.status == 403
      refute_received {:guest_code, _, _, _}

      assert request(:post, "/support/widget/lookup", %{
               email: "recipient@example.test",
               verification_id: Ecto.UUID.generate(),
               verification_code: "12345678",
               reference: ticket.reference
             }).status == 403
    end

    test "serves no ticket reads or replies", %{ticket: ticket, token: token} do
      header = [{"x-guest-access-token", token}]
      replies = Escalated.repo().aggregate(Escalated.Schemas.Reply, :count)

      assert request(:get, "/support/widget/tickets/#{ticket.reference}", nil, header).status ==
               403

      assert request(
               :post,
               "/support/widget/tickets/#{ticket.reference}/reply",
               %{body: "x"},
               header
             ).status ==
               403

      assert Escalated.repo().aggregate(Escalated.Schemas.Reply, :count) == replies
    end

    test "serves no chat traffic", %{chat_token: token} do
      assert request(:get, "/support/widget/chat/#{token}/messages").status == 403
      assert request(:post, "/support/widget/chat/#{token}/messages", %{body: "x"}).status == 403
      assert request(:post, "/support/widget/chat/#{token}/typing").status == 403
      assert request(:post, "/support/widget/chat/#{token}/end").status == 403
      assert request(:get, "/support/widget/chat/availability").status == 403
    end

    test "still reports its disabled configuration" do
      resp = request(:get, "/support/widget/config")
      assert resp.status == 200
      assert Jason.decode!(resp.resp_body)["enabled"] == false
    end

    test "leaves the non-widget guest routes available", %{token: token} do
      assert request(:post, "/support/guest/verification", %{
               email: "recipient@example.test",
               purpose: "lookup"
             }).status == 202

      assert request(:get, "/support/api/v1/guest/tickets/#{token}").status == 200
    end
  end

  describe "guest capability headers" do
    setup do
      {:ok, ticket, result} = TicketService.create_guest(Helpers.proof(), attrs())
      %{ticket: ticket, token: result["guest_access_token"]}
    end

    test "API guest reads accept the documented headers", %{ticket: ticket, token: token} do
      for header <- [{"x-guest-access-token", token}, {"authorization", "Bearer " <> token}] do
        resp = request(:get, "/support/api/v1/guest/tickets/header", nil, [header])
        assert resp.status == 200
        assert Jason.decode!(resp.resp_body)["data"]["reference"] == ticket.reference
      end
    end

    test "API guest replies accept the documented headers", %{token: token} do
      for header <- [{"x-guest-access-token", token}, {"authorization", "Bearer " <> token}] do
        assert request(:post, "/support/api/v1/guest/tickets/header/replies", %{body: "hi"}, [
                 header
               ]).status ==
                 201
      end
    end

    test "guest CSAT accepts the documented header", %{ticket: ticket, token: token} do
      Escalated.repo().update!(Ecto.Changeset.change(ticket, status: "resolved"))

      assert request(:post, "/support/guest/tickets/header/rate", %{rating: 5}, [
               {"x-guest-access-token", token}
             ]).status == 201

      assert Escalated.repo().aggregate(SatisfactionRating, :count) == 1
    end

    test "an invalid header does not fall back to a different path capability",
         %{token: token} do
      assert request(:get, "/support/api/v1/guest/tickets/#{token}", nil, [
               {"x-guest-access-token", "invalid"}
             ]).status == 404
    end
  end
end
