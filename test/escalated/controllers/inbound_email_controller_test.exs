defmodule Escalated.Controllers.InboundEmailControllerTest do
  @moduledoc """
  HTTP-boundary tests for Escalated.Controllers.InboundEmailController.

  Mirrors the Go (escalated-go#34), .NET (escalated-dotnet#28), and
  Spring (escalated-spring#31) controller-test ports.

  The controller calls `Escalated.repo()` + `TicketService.create/1` on
  the success path, which would require a live Ecto repo. These tests
  cover the boundary that doesn't touch the repo: signature
  verification, adapter dispatch, unknown-adapter fallback, and
  parser-failure responses. The reply/create orchestration itself is
  covered end-to-end in
  `test/escalated/services/email/inbound/service_test.exs`.
  """

  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn, only: [put_req_header: 3, put_private: 3]

  alias Escalated.Controllers.InboundEmailController

  @secret "test-inbound-secret"

  # Always-fails parser so we can exercise the 400/401 branches without
  # standing up a real Ecto repo (which the success path requires).
  defmodule FailingParser do
    def name, do: "postmark"
    def parse(_), do: {:error, :stubbed_out}
  end

  setup do
    prev_secret = Application.get_env(:escalated, :email_inbound_secret)
    prev_parsers = Application.get_env(:escalated, :inbound_parsers)

    Application.put_env(:escalated, :email_inbound_secret, @secret)
    Application.put_env(:escalated, :inbound_parsers, [FailingParser])

    on_exit(fn ->
      put_or_delete(:email_inbound_secret, prev_secret)
      put_or_delete(:inbound_parsers, prev_parsers)
    end)

    :ok
  end

  defp put_or_delete(key, nil), do: Application.delete_env(:escalated, key)
  defp put_or_delete(key, val), do: Application.put_env(:escalated, key, val)

  defp build_conn(params, opts \\ []) do
    secret = Keyword.get(opts, :secret, @secret)

    conn = conn(:post, "/support/webhook/email/inbound", params)

    conn =
      if secret,
        do: put_req_header(conn, "x-escalated-inbound-secret", secret),
        else: conn

    conn
    |> put_private(:phoenix_endpoint, FakeEndpoint)
    |> put_private(:phoenix_router, FakeRouter)
  end

  describe "inbound/2 — auth + dispatch" do
    test "401 when secret header is missing" do
      conn = build_conn(%{"adapter" => "postmark"}, secret: nil)
      conn = InboundEmailController.inbound(conn, conn.body_params)
      assert conn.status == 401
      body = Jason.decode!(conn.resp_body)
      assert body["error"] =~ "inbound secret"
    end

    test "401 when secret header is wrong" do
      conn = build_conn(%{"adapter" => "postmark"}, secret: "nope")
      conn = InboundEmailController.inbound(conn, conn.body_params)
      assert conn.status == 401
    end

    test "400 when adapter is missing" do
      conn = build_conn(%{})
      conn = InboundEmailController.inbound(conn, conn.body_params)
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "adapter"
    end

    test "400 for unknown adapter" do
      conn = build_conn(%{"adapter" => "nonesuch"})
      conn = InboundEmailController.inbound(conn, conn.body_params)
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] =~ "unknown adapter"
    end

    test "adapter can be provided via x-escalated-adapter header" do
      # No `adapter` query param; use the header path instead. The
      # FailingParser always returns :error so we land on the 400
      # "invalid payload" branch — that would produce "unknown adapter"
      # if the adapter-header dispatch wasn't working, so the body
      # content distinguishes the two cases.
      conn =
        %{}
        |> build_conn()
        |> put_req_header("x-escalated-adapter", "postmark")

      conn = InboundEmailController.inbound(conn, conn.body_params)

      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "invalid payload"
    end

    test "parser error returns 400 invalid payload (not 500)" do
      conn = build_conn(%{"adapter" => "postmark", "something" => "else"})
      conn = InboundEmailController.inbound(conn, conn.body_params)
      assert conn.status == 400
      assert Jason.decode!(conn.resp_body)["error"] == "invalid payload"
    end
  end
end
