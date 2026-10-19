defmodule Escalated.Controllers.WidgetContractTest do
  @moduledoc """
  The requests the shared widget (`@escalated-dev/escalated`,
  `src/widget/EscalatedWidget.vue`) sends, and the fields it reads from each
  answer: `/config`, knowledge-base search and articles, ticket and chat
  creation with a department, chat message authors, and the verified status
  view. Requests come from an embedding site through a host router mounted
  the way the README recommends, so the widget's CORS covers every route.
  """
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{AgentProfile, Article, ArticleCategory, Department, Reply, Ticket}
  alias Escalated.Test.{GuestAccessHelpers, WidgetEmbedRouter}
  alias Escalated.TestRepo

  @host "https://help.example.com"
  @shop "https://shop.example.com"

  setup do
    GuestAccessHelpers.configure()

    keys = [
      :widget_allowed_origins,
      :widget_settings,
      :rate_limit_backend,
      :knowledge_base_enabled,
      :knowledge_base_public
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :widget_allowed_origins, [@shop])
    Application.delete_env(:escalated, :widget_settings)
    Application.delete_env(:escalated, :rate_limit_backend)
    Application.put_env(:escalated, :knowledge_base_enabled, true)
    Application.put_env(:escalated, :knowledge_base_public, true)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  describe "GET /config" do
    test "returns the top-level keys the widget reads" do
      sales = TestRepo.insert!(%Department{name: "Sales", slug: "sales", is_active: true})
      TestRepo.insert!(%Department{name: "Archive", slug: "archive", is_active: false})

      body = json(request(:get, "/support/widget/config"))

      assert body["color"] == "#4F46E5"
      assert body["primary_color"] == "#4F46E5"
      assert body["position"] == "bottom-right"
      assert body["greeting"] == "How can we help you?"
      assert body["departments"] == [%{"id" => sales.id, "name" => "Sales"}]
      assert body["kb_enabled"] == true
      assert body["guest_tickets_enabled"] == true
      assert body["accepts_metadata"] == true
      assert body["guest_verification_required"] == true
      assert body["status_lookup_enabled"] == true
      assert body["widget"]["color"] == "#4F46E5"
    end

    test "uses the host's colour and position" do
      Application.put_env(:escalated, :widget_settings, %{
        primary_color: "#112233",
        position: "bottom-left"
      })

      body = json(request(:get, "/support/widget/config"))

      assert body["color"] == "#112233"
      assert body["position"] == "bottom-left"
    end

    test "reports the knowledge base off when it is disabled" do
      Application.put_env(:escalated, :knowledge_base_enabled, false)

      assert json(request(:get, "/support/widget/config"))["kb_enabled"] == false
    end

    test "reports the knowledge base off to visitors when it is not public" do
      Application.put_env(:escalated, :knowledge_base_public, false)

      assert json(request(:get, "/support/widget/config"))["kb_enabled"] == false
    end
  end

  describe "GET /articles" do
    test "searches published articles" do
      category = TestRepo.insert!(%ArticleCategory{name: "Shipping", slug: "shipping"})

      article(%{
        title: "Tracking a parcel",
        slug: "tracking-a-parcel",
        body: "<p>Use the <strong>tracking</strong> link in your parcel email.</p>",
        category_id: category.id
      })

      article(%{title: "Parcel drafts", slug: "parcel-drafts", status: "draft"})

      conn = request(:get, "/support/widget/articles?q=parcel")

      assert conn.status == 200

      assert json(conn) == %{
               "articles" => [
                 %{
                   "title" => "Tracking a parcel",
                   "slug" => "tracking-a-parcel",
                   "excerpt" => "Use the tracking link in your parcel email."
                 }
               ]
             }
    end

    test "cuts long excerpts" do
      article(%{title: "Long parcel story", slug: "long", body: String.duplicate("word ", 100)})

      [found] = json(request(:get, "/support/widget/articles?q=parcel"))["articles"]

      assert String.length(found["excerpt"]) <= 153
      assert String.ends_with?(found["excerpt"], "...")
    end

    test "asks for at least two characters" do
      conn = request(:get, "/support/widget/articles?q=p")

      assert conn.status == 422
      assert %{"message" => _, "errors" => %{"q" => [_ | _]}} = json(conn)
    end

    test "is not found while the knowledge base is off" do
      Application.put_env(:escalated, :knowledge_base_enabled, false)

      assert request(:get, "/support/widget/articles?q=parcel").status == 404
    end

    test "is forbidden to visitors while the knowledge base is not public" do
      Application.put_env(:escalated, :knowledge_base_public, false)

      assert request(:get, "/support/widget/articles?q=parcel").status == 403
    end

    test "is refused while the widget is disabled" do
      Application.put_env(:escalated, :widget_settings, %{enabled: false})

      assert request(:get, "/support/widget/articles?q=parcel").status == 403
    end

    test "is open to sites allowed to embed the widget" do
      article(%{title: "Tracking a parcel", slug: "tracking-a-parcel"})

      conn = request(:get, "/support/widget/articles?q=parcel", nil, origin: @shop)

      assert conn.status == 200
      assert header(conn, "access-control-allow-origin") == @shop

      preflight =
        request(:options, "/support/widget/articles/tracking-a-parcel", nil,
          origin: @shop,
          headers: [{"access-control-request-method", "GET"}]
        )

      assert preflight.status == 204
      assert header(preflight, "access-control-allow-origin") == @shop
    end
  end

  describe "GET /articles/:slug" do
    test "returns the article at the top level and counts the view" do
      category = TestRepo.insert!(%ArticleCategory{name: "Shipping", slug: "shipping"})

      saved =
        article(%{
          title: "Tracking a parcel",
          slug: "tracking-a-parcel",
          body: "<p>Use the link.</p>",
          category_id: category.id
        })

      conn = request(:get, "/support/widget/articles/tracking-a-parcel", nil, origin: @shop)

      assert conn.status == 200
      assert header(conn, "access-control-allow-origin") == @shop

      assert json(conn) == %{
               "title" => "Tracking a parcel",
               "slug" => "tracking-a-parcel",
               "body" => "<p>Use the link.</p>",
               "category" => "Shipping"
             }

      assert TestRepo.get!(Article, saved.id).view_count == 1
    end

    test "does not show drafts or unknown articles" do
      article(%{title: "Secret", slug: "secret", status: "draft"})

      assert request(:get, "/support/widget/articles/secret").status == 404
      assert request(:get, "/support/widget/articles/missing").status == 404
    end

    test "follows the knowledge base settings" do
      article(%{title: "Tracking a parcel", slug: "tracking-a-parcel"})

      Application.put_env(:escalated, :knowledge_base_public, false)
      assert request(:get, "/support/widget/articles/tracking-a-parcel").status == 403

      Application.put_env(:escalated, :knowledge_base_enabled, false)
      assert request(:get, "/support/widget/articles/tracking-a-parcel").status == 404
    end
  end

  describe "POST /tickets" do
    test "files the ticket under the chosen department" do
      sales = TestRepo.insert!(%Department{name: "Sales", slug: "sales", is_active: true})

      conn =
        request(:post, "/support/widget/tickets", ticket_params(%{"department_id" => sales.id}))

      assert conn.status == 201
      body = json(conn)
      assert is_binary(body["reference"])
      assert is_binary(body["message"])
      assert TestRepo.one!(Ticket).department_id == sales.id
    end

    test "accepts the department as a string" do
      sales = TestRepo.insert!(%Department{name: "Sales", slug: "sales", is_active: true})
      params = ticket_params(%{"department_id" => Integer.to_string(sales.id)})

      assert request(:post, "/support/widget/tickets", params).status == 201
      assert TestRepo.one!(Ticket).department_id == sales.id
    end

    test "ignores inactive, unknown and malformed departments" do
      archive = TestRepo.insert!(%Department{name: "Archive", slug: "archive", is_active: false})

      [archive.id, archive.id + 1000, "sales", nil]
      |> Enum.with_index()
      |> Enum.each(fn {department_id, n} ->
        # A fresh mailbox each time: verification codes are rate limited per address.
        params =
          ticket_params(%{"department_id" => department_id}, "recipient#{n}@example.test")

        assert request(:post, "/support/widget/tickets", params).status == 201
      end)

      assert TestRepo.all(Ticket) |> Enum.map(& &1.department_id) == [nil, nil, nil, nil]
    end
  end

  describe "live chat" do
    test "starts the chat under the chosen department" do
      sales = TestRepo.insert!(%Department{name: "Sales", slug: "sales", is_active: true})

      conn =
        request(:post, "/support/widget/chat/start", chat_params(%{"department_id" => sales.id}))

      assert conn.status == 201
      assert TestRepo.one!(Ticket).department_id == sales.id
    end

    test "names the author of every message" do
      conn = request(:post, "/support/widget/chat/start", chat_params())
      id = json(conn)["id"]
      ticket = TestRepo.one!(Ticket)

      assert request(:post, "/support/widget/chat/#{id}/messages", %{"body" => "Hi"}).status ==
               201

      TestRepo.insert!(%AgentProfile{user_id: 42, display_name: "Dana"})
      TestRepo.insert!(%Reply{ticket_id: ticket.id, body: "Hello, Dana here", author_id: 42})

      TestRepo.insert!(%Reply{
        ticket_id: ticket.id,
        body: "Private",
        author_id: 42,
        is_internal: true
      })

      TestRepo.insert!(%Reply{ticket_id: ticket.id, body: "Anyone?", author_id: 43})

      body = json(request(:get, "/support/widget/chat/#{id}/messages"))

      assert Enum.map(body["messages"], &{&1["body"], &1["is_agent"], &1["author"]}) == [
               {"Hi", false, %{"name" => "Recipient"}},
               {"Hello, Dana here", true, %{"name" => "Dana"}},
               {"Anyone?", true, %{"name" => "Support"}}
             ]

      assert Enum.all?(body["messages"], &(is_integer(&1["id"]) and &1["created_at"]))
    end
  end

  describe "verified status view" do
    test "shows the status label and who wrote each reply" do
      conn = request(:post, "/support/widget/tickets", ticket_params())
      %{"reference" => reference, "guest_access_token" => token} = json(conn)
      ticket = TestRepo.one!(Ticket)

      TestRepo.insert!(%AgentProfile{user_id: 42, display_name: "Dana"})
      TestRepo.insert!(%Reply{ticket_id: ticket.id, body: "On its way", author_id: 42})
      TestRepo.insert!(%Reply{ticket_id: ticket.id, body: "Thanks!"})

      conn =
        request(:get, "/support/widget/tickets/#{reference}", nil,
          headers: [{"authorization", "Bearer " <> token}]
        )

      assert conn.status == 200
      body = json(conn)
      assert body["reference"] == reference
      assert body["status"] == "open"
      assert body["status_label"] == "Open"
      assert body["status_color"] == "#3B82F6"

      assert Enum.map(body["replies"], &{&1["body"], &1["author"], &1["is_agent"]}) == [
               {"On its way", "Dana", true},
               {"Thanks!", "Recipient", false}
             ]

      assert body["ticket"]["status_label"] == "Open"
    end
  end

  defp article(attrs) do
    %Article{}
    |> Article.changeset(Map.merge(%{status: "published", body: "About parcels"}, attrs))
    |> TestRepo.insert!()
  end

  defp ticket_params(extra \\ %{}, email \\ "recipient@example.test") do
    %{
      "name" => "Recipient",
      "subject" => "Parcel question",
      "description" => "Where is my parcel?"
    }
    |> Map.merge(GuestAccessHelpers.proof(email))
    |> Map.merge(extra)
  end

  defp chat_params(extra \\ %{}) do
    %{"name" => "Recipient", "message" => "Hello"}
    |> Map.merge(GuestAccessHelpers.proof("recipient@example.test", "chat"))
    |> Map.merge(extra)
  end

  defp request(method, path, body \\ nil, opts \\ []) do
    conn =
      conn(method, @host <> path, if(is_nil(body), do: nil, else: Jason.encode!(body)))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> Map.put(:remote_ip, {10, 1, :rand.uniform(250), :rand.uniform(250)})
      |> init_test_session(%{})

    # Requests come from a site allowed to embed the widget, the way an
    # embedded widget sends them: no CSRF token, CORS on every answer.
    conn = put_req_header(conn, "origin", Keyword.get(opts, :origin, @shop))

    conn =
      Enum.reduce(opts[:headers] || [], conn, fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    WidgetEmbedRouter.call(conn, WidgetEmbedRouter.init([]))
  end

  defp header(conn, name), do: conn |> get_resp_header(name) |> Enum.join(", ")

  defp json(conn), do: Jason.decode!(conn.resp_body)
end
