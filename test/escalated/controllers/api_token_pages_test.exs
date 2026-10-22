defmodule Escalated.Controllers.ApiTokenPagesTest do
  @moduledoc """
  API tokens (escalated-laravel's `ApiToken`, `AuthenticateApiToken` and
  `Admin\\ApiTokenController`): the admin page and its writes through the
  router, and bearer authentication on the JSON ticket API.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.HostTestRepo
  alias Escalated.Schemas.{ApiToken, Reply}
  alias Escalated.Services.{ApiTokenService, TicketService}

  @base "/support/admin/api-tokens"
  @api "/support/api/v1/tickets"

  defp repo, do: Escalated.repo()

  setup do
    Application.put_env(:escalated, :api_tokens_enabled, true)

    on_exit(fn ->
      Enum.each(
        [:api_tokens_enabled, :api_token_validator],
        &Application.delete_env(:escalated, &1)
      )
    end)

    %{
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      agent: host_user!(%{name: "Arno Agent", is_agent: true}),
      customer: host_user!(%{name: "Cora Customer"})
    }
  end

  defp token!(user, abilities \\ ["agent"], expires_at \\ nil) do
    {:ok, %{token: token, plain_text_token: plain}} =
      ApiTokenService.create(user.id, "CI", abilities, expires_at)

    {token, plain}
  end

  defp api(method, path, plain, body \\ nil) do
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
    |> put_req_header("accept", "application/json")
    |> then(fn conn ->
      if plain, do: put_req_header(conn, "authorization", "Bearer " <> plain), else: conn
    end)
    |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
  end

  defp ticket! do
    {:ok, ticket} =
      TicketService.create(%{
        subject: "Printer on fire",
        description: "Body",
        requester_id: 4242,
        requester_type: "user"
      })

    ticket
  end

  describe "Admin/ApiTokens/Index" do
    test "sends tokens, users and api_enabled with Laravel's row keys", ctx do
      {token, plain} = token!(ctx.agent, ["agent", "admin"])

      conn = visit(:get, @base, ctx.admin)
      props = page!(conn, "Escalated/Admin/ApiTokens/Index")

      assert_keys(props, ~w(tokens users api_enabled))
      assert props["api_enabled"] == true

      [row] = props["tokens"]

      assert_keys(
        row,
        ~w(id name user_name user_email abilities last_used_at last_used_ip expires_at is_expired created_at),
        "token"
      )

      assert row["id"] == token.id
      assert row["user_name"] == "Arno Agent"
      assert row["user_email"] == ctx.agent.email
      assert row["abilities"] == ["agent", "admin"]
      assert row["is_expired"] == false
      refute Map.has_key?(row, "token")

      # Neither the token nor its digest ever reaches the page.
      refute conn.resp_body =~ plain
      refute conn.resp_body =~ ApiTokenService.digest(plain)
      assert get_resp_header(conn, "cache-control") == ["no-store"]

      users = props["users"]
      assert_keys(hd(users), ~w(id name email), "user")
      ids = Enum.map(users, & &1["id"])
      assert ctx.agent.id in ids
      refute ctx.customer.id in ids
    end

    test "api_enabled is false until the host turns tokens on", ctx do
      Application.delete_env(:escalated, :api_tokens_enabled)

      props = visit(:get, @base, ctx.admin) |> page!("Escalated/Admin/ApiTokens/Index")
      assert props["api_enabled"] == false
    end

    test "an expired token is flagged", ctx do
      token!(ctx.agent, ["agent"], DateTime.add(DateTime.utc_now(), -60, :second))

      props = visit(:get, @base, ctx.admin) |> page!("Escalated/Admin/ApiTokens/Index")
      [row] = props["tokens"]
      assert row["is_expired"] == true
      assert is_binary(row["expires_at"])
    end

    test "agents who are not admins cannot open it", ctx do
      assert visit(:get, @base, ctx.agent).status == 403
      assert visit(:post, @base, ctx.agent, %{"name" => "x"}).status == 403
    end
  end

  describe "store" do
    test "creates a token, stores only its digest and flashes the plain text once", ctx do
      conn =
        visit(:post, @base, ctx.admin, %{
          "name" => "Zapier",
          "user_id" => ctx.agent.id,
          "abilities" => ["agent"],
          "expires_in_days" => 30
        })

      assert conn.status in [302, 303]
      assert location(conn) == @base

      plain = Phoenix.Flash.get(conn.assigns.flash, :plain_text_token)
      assert plain =~ ~r/\A[0-9a-f]{64}\z/
      assert Phoenix.Flash.get(conn.assigns.flash, :success) == "API token created."

      token = repo().get_by!(ApiToken, name: "Zapier")
      assert token.user_id == ctx.agent.id
      assert token.abilities == ["agent"]
      assert token.token == ApiTokenService.digest(plain)
      refute token.token == plain
      assert_in_delta DateTime.diff(token.expires_at, DateTime.utc_now()), 30 * 86_400, 60

      # The page after the redirect is where useForm's onSuccess reads it.
      props =
        conn(:get, @base)
        |> init_test_session(%{"phoenix_flash" => %{"plain_text_token" => plain}})
        |> assign(:current_user, ctx.admin)
        |> put_req_header("x-inertia", "true")
        |> put_req_header("x-inertia-version", inertia_version())
        |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
        |> page!("Escalated/Admin/ApiTokens/Index")

      assert props["flash"]["plain_text_token"] == plain
    end

    test "a JSON client gets the plain text in a 201", ctx do
      conn =
        conn(
          :post,
          @base,
          Jason.encode!(%{"name" => "Script", "user_id" => ctx.agent.id, "abilities" => ["*"]})
        )
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> init_test_session(%{})
        |> assign(:current_user, ctx.admin)
        |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))

      assert conn.status == 201
      body = Jason.decode!(conn.resp_body)
      assert body["token"]["name"] == "Script"
      assert body["token"]["abilities"] == ["*"]

      assert ApiTokenService.find_by_plain_text(body["plain_text_token"]).id ==
               body["token"]["id"]
    end

    test "invalid input is refused with Laravel's fields", ctx do
      for {body, field} <- [
            {%{"user_id" => ctx.agent.id, "abilities" => ["agent"]}, "name"},
            {%{"name" => "x", "abilities" => ["agent"]}, "user_id"},
            {%{"name" => "x", "user_id" => ctx.customer.id, "abilities" => ["agent"]}, "user_id"},
            {%{"name" => "x", "user_id" => 999_999, "abilities" => ["agent"]}, "user_id"},
            {%{"name" => "x", "user_id" => ctx.agent.id, "abilities" => []}, "abilities"},
            {%{"name" => "x", "user_id" => ctx.agent.id, "abilities" => ["root"]}, "abilities"},
            {%{
               "name" => "x",
               "user_id" => ctx.agent.id,
               "abilities" => ["agent"],
               "expires_in_days" => 400
             }, "expires_in_days"}
          ] do
        conn = visit(:post, @base, ctx.admin, body)
        assert conn.status in [302, 303], "#{field}: #{conn.status}"
        errors = conn |> fetch_session() |> get_session("inertia_errors") || %{}

        assert Map.has_key?(Map.new(errors, fn {k, v} -> {to_string(k), v} end), field),
               "expected an error on #{field} for #{inspect(body)}, got #{inspect(errors)}"
      end

      assert repo().aggregate(ApiToken, :count) == 0
    end
  end

  describe "update and destroy" do
    test "update changes the name and abilities", ctx do
      {token, _} = token!(ctx.agent)

      conn =
        visit(:patch, "#{@base}/#{token.id}", ctx.admin, %{
          "name" => "Renamed",
          "abilities" => ["agent", "admin"]
        })

      assert conn.status in [302, 303]
      updated = repo().get!(ApiToken, token.id)
      assert updated.name == "Renamed"
      assert updated.abilities == ["agent", "admin"]
      assert updated.token == token.token

      assert visit(:patch, "#{@base}/#{token.id}", ctx.admin, %{"abilities" => ["root"]}).status in [
               302,
               303
             ]

      assert repo().get!(ApiToken, token.id).abilities == ["agent", "admin"]
    end

    test "destroy revokes the token, and the API stops accepting it", ctx do
      {token, plain} = token!(ctx.agent)
      assert api(:get, @api, plain).status == 200

      conn = visit(:delete, "#{@base}/#{token.id}", ctx.admin)
      assert conn.status in [302, 303]
      assert repo().get(ApiToken, token.id) == nil

      assert api(:get, @api, plain).status == 401
      assert visit(:delete, "#{@base}/#{token.id}", ctx.admin).status == 404
    end
  end

  describe "bearer authentication on the ticket API" do
    test "an agent token acts as its owner and records its use", ctx do
      ticket = ticket!()
      {token, plain} = token!(ctx.agent)

      conn = api(:get, "#{@api}/#{ticket.reference}", plain)
      assert conn.status == 200

      used = repo().get!(ApiToken, token.id)
      assert used.last_used_ip == "127.0.0.1"
      assert used.last_used_at

      conn = api(:post, "#{@api}/#{ticket.reference}/reply", plain, %{"body" => "On it"})
      assert conn.status in [200, 201]

      reply =
        from(r in Reply, where: r.ticket_id == ^ticket.id, order_by: [desc: r.id], limit: 1)
        |> repo().one!()

      assert to_string(reply.author_id) == to_string(ctx.agent.id)
    end

    test "a * token works; an admin-only token is refused 403", ctx do
      {_, all} = token!(ctx.agent, ["*"])
      {_, admin_only} = token!(ctx.admin, ["admin"])

      assert api(:get, @api, all).status == 200
      assert api(:get, @api, admin_only).status == 403
    end

    test "expired, unknown and missing tokens get 401", ctx do
      {_, expired} = token!(ctx.agent, ["agent"], DateTime.add(DateTime.utc_now(), -1, :second))

      assert api(:get, @api, expired).status == 401
      assert Jason.decode!(api(:get, @api, expired).resp_body)["error"] == "Token has expired."
      assert api(:get, @api, String.duplicate("a", 64)).status == 401
      assert api(:get, @api, nil).status == 401
    end

    test "an owner who is no longer an agent gets 403; a deleted owner 401", ctx do
      {_, plain} = token!(ctx.agent)

      HostTestRepo.get!(HostUser, ctx.agent.id)
      |> Ecto.Changeset.change(is_agent: false)
      |> HostTestRepo.update!()

      assert api(:get, @api, plain).status == 403

      HostTestRepo.get!(HostUser, ctx.agent.id) |> HostTestRepo.delete!()
      conn = api(:get, @api, plain)
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] == "Token owner not found."
    end

    test "tokens are refused until the host turns them on", ctx do
      Application.delete_env(:escalated, :api_tokens_enabled)
      {token, plain} = token!(ctx.agent)

      assert api(:get, @api, plain).status == 401
      assert repo().get!(ApiToken, token.id).last_used_at == nil
    end

    test "the host's own bearer tokens keep working with tokens on", ctx do
      agent = ctx.agent

      Application.put_env(:escalated, :api_token_validator, fn
        "host-session-token" -> {:ok, agent}
        _ -> :error
      end)

      {_, plain} = token!(ctx.agent)

      assert api(:get, @api, "host-session-token").status == 200
      assert api(:get, @api, plain).status == 200
      assert api(:get, @api, "forged").status == 401
    end
  end

  describe "ApiTokenService" do
    test "stores the digest, finds by plain text and throttles touches", ctx do
      {token, plain} = token!(ctx.agent)

      assert token.token == :crypto.hash(:sha256, plain) |> Base.encode16(case: :lower)
      assert ApiTokenService.find_by_plain_text(plain).id == token.id
      assert ApiTokenService.find_by_plain_text(token.token) == nil
      assert ApiTokenService.find_by_plain_text("") == nil
      refute inspect(token) =~ token.token

      {:ok, first} = ApiTokenService.touch(token, "10.0.0.1")
      {:ok, second} = ApiTokenService.touch(first, "10.0.0.2")
      assert second.last_used_ip == "10.0.0.1"

      stale = %{second | last_used_at: DateTime.add(second.last_used_at, -301, :second)}
      {:ok, third} = ApiTokenService.touch(stale, "10.0.0.3")
      assert third.last_used_ip == "10.0.0.3"
    end
  end
end
