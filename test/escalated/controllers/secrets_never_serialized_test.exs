defmodule Escalated.Controllers.SecretsNeverSerializedTest do
  @moduledoc """
  Stored secrets never reach the browser (escalated-laravel's
  `SecretsNeverSerializedTest`).

  Import source credentials and webhook signing secrets are kept server-side
  so the app can use them. None of them is shown back to an admin: every page
  and JSON response that carries one of these records is checked here, through
  the router, for the raw secret anywhere in the body.

  Surfaces Laravel has that this package does not: SSO settings (no SSO here),
  inbound email secrets on a settings page (they are host config,
  `:email_inbound_secret`, never a stored setting) and API tokens (the host
  authenticates API requests, `Escalated.Api.HostAuth`; there is no token
  table). Two-factor records have no page or JSON surface; their schema still
  redacts the seed and recovery codes.
  """
  use Escalated.PageCase

  alias Escalated.Import.{Credentials, Runner}
  alias Escalated.Schemas.{ImportJob, TwoFactor, Webhook, WebhookDelivery}
  alias Escalated.Test.FakeImportAdapter, as: Fake

  @import_base "/support/admin/import"
  @webhooks "/support/admin/webhooks"
  @webhook_secret "whsec-4c8e1a7b9d3f"

  defp repo, do: Escalated.repo()

  setup do
    previous =
      Map.new(
        [:filters, :import_secret, :email_inbound_secret],
        &{&1, Application.get_env(:escalated, &1)}
      )

    Application.put_env(:escalated, :filters, %{
      "import.adapters" => [fn adapters -> adapters ++ [Fake] end]
    })

    Application.put_env(:escalated, :import_secret, String.duplicate("import-secret-", 4))

    on_exit(fn ->
      Runner.await_all()

      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:escalated, key)
        {key, value} -> Application.put_env(:escalated, key, value)
      end)
    end)

    %{admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})}
  end

  # A visit that carries the session from the previous one, as a browser does.
  defp request(method, path, user, body \\ nil, session \\ %{}, opts \\ []) do
    base =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    base =
      base
      |> init_test_session(session)
      |> assign(:current_user, user)

    base =
      if Keyword.get(opts, :inertia, true),
        do:
          base
          |> put_req_header("x-inertia", "true")
          |> put_req_header("x-inertia-version", inertia_version()),
        else: put_req_header(base, "accept", "application/json")

    Escalated.Test.Router.call(base, Escalated.Test.Router.init([]))
  end

  defp refute_secrets(conn, secrets) do
    Enum.each(secrets, fn secret ->
      refute conn.resp_body =~ secret,
             "#{conn.request_path} sent the stored secret #{inspect(secret)}"
    end)

    conn
  end

  defp import_job! do
    %ImportJob{}
    |> ImportJob.changeset(%{
      platform: "fakedesk",
      status: "importing",
      credentials: Credentials.seal(Fake.credentials()),
      progress: %{
        "tickets" => %{"total" => 10, "processed" => 4, "skipped" => 0, "failed" => 0}
      },
      error_log:
        Enum.map(1..60, fn i ->
          %{"entity_type" => "tickets", "source_id" => "k#{i}", "error" => "boom #{i}"}
        end)
    })
    |> repo().insert!()
  end

  # The raw token, and the sealed form the job stores.
  defp import_secrets(job), do: [Fake.token(), job.credentials]

  describe "import" do
    test "the index page lists jobs without their credentials", %{admin: admin} do
      job = import_job!()

      conn = request(:get, @import_base, admin) |> refute_secrets(import_secrets(job))
      [row] = page!(conn, "Escalated/Admin/Import/Index")["jobs"]

      assert_keys(row, ~w(id platform status progress field_mappings error_log created_at))
      assert row["id"] == job.id
      refute Map.has_key?(row, "credentials")
    end

    test "the progress page and status json carry no credentials", %{admin: admin} do
      job = import_job!()

      conn =
        request(:get, "#{@import_base}/progress/#{job.id}", admin)
        |> refute_secrets(import_secrets(job))

      props = page!(conn, "Escalated/Admin/Import/Progress")["job"]

      assert_keys(
        props,
        ~w(id platform status progress field_mappings error_log started_at completed_at created_at)
      )

      refute Map.has_key?(props, "credentials")
      assert props["progress"]["tickets"]["processed"] == 4
      # The last 50 errors, as the status poll sends.
      assert length(props["error_log"]) == 50
      assert List.last(props["error_log"])["source_id"] == "k60"

      status =
        request(:get, "#{@import_base}/status/#{job.id}", admin, nil, %{}, inertia: false)
        |> refute_secrets(import_secrets(job))

      assert Jason.decode!(status.resp_body)["status"] == "importing"
    end

    test "the connect, test-connection, mapping and review steps never echo credentials",
         %{admin: admin} do
      secrets = [Fake.token()]

      request(:get, "#{@import_base}/fakedesk/connect", admin) |> refute_secrets(secrets)

      connected =
        request(
          :post,
          "#{@import_base}/fakedesk/test-connection",
          admin,
          %{credentials: Fake.credentials()},
          %{},
          inertia: false
        )
        |> refute_secrets(secrets)

      assert Jason.decode!(connected.resp_body) == %{"success" => true}
      session = Plug.Conn.get_session(connected)

      request(:get, "#{@import_base}/fakedesk/mapping", admin, nil, session)
      |> refute_secrets(secrets ++ Map.values(session))

      request(
        :post,
        "#{@import_base}/fakedesk/review",
        admin,
        %{entity_types: ["tickets"]},
        session
      )
      |> refute_secrets(secrets ++ Map.values(session))
    end

    test "the import run still reads the stored credentials server-side" do
      job = import_job!()

      assert Credentials.open(repo().get!(ImportJob, job.id).credentials) == Fake.credentials()
    end
  end

  defp webhook!(attrs \\ %{}) do
    %Webhook{}
    |> Webhook.changeset(
      Map.merge(
        %{
          url: "https://hooks.example.test/escalated",
          events: ["ticket.created"],
          secret: @webhook_secret,
          active: true
        },
        attrs
      )
    )
    |> repo().insert!()
  end

  describe "webhooks" do
    test "the index, edit and delivery-log pages show has_secret, never the secret",
         %{admin: admin} do
      webhook = webhook!()

      repo().insert!(%WebhookDelivery{
        webhook_id: webhook.id,
        event: "ticket.created",
        payload: %{"ok" => true},
        response_code: 200,
        attempts: 1
      })

      index = request(:get, @webhooks, admin) |> refute_secrets([@webhook_secret])
      [row] = page!(index, "Escalated/Admin/Webhooks/Index")["webhooks"]
      assert row["has_secret"] == true
      refute Map.has_key?(row, "secret")

      edit =
        request(:get, "#{@webhooks}/#{webhook.id}/edit", admin)
        |> refute_secrets([@webhook_secret])

      props = page!(edit, "Escalated/Admin/Webhooks/Form")["webhook"]
      assert props["has_secret"] == true
      assert props["url"] == "https://hooks.example.test/escalated"
      refute Map.has_key?(props, "secret")

      log =
        request(:get, "#{@webhooks}/#{webhook.id}/deliveries", admin)
        |> refute_secrets([@webhook_secret])

      assert page!(log, "Escalated/Admin/Webhooks/DeliveryLog")["webhook"]["has_secret"] == true
    end

    test "has_secret is false for a webhook without one", %{admin: admin} do
      webhook = webhook!(%{secret: nil})

      edit = request(:get, "#{@webhooks}/#{webhook.id}/edit", admin)
      assert page!(edit, "Escalated/Admin/Webhooks/Form")["webhook"]["has_secret"] == false
    end

    test "saving with the secret left blank keeps the stored secret", %{admin: admin} do
      webhook = webhook!()

      conn =
        request(:put, "#{@webhooks}/#{webhook.id}", admin, %{
          url: "https://hooks.example.test/escalated",
          events: ["ticket.created", "ticket.updated"],
          secret: "",
          clear_secret: false,
          active: true
        })

      assert conn.status in [302, 303]
      stored = repo().get!(Webhook, webhook.id)
      assert stored.secret == @webhook_secret
      assert stored.events == ["ticket.created", "ticket.updated"]

      # A form that leaves the field out entirely keeps it too.
      request(:put, "#{@webhooks}/#{webhook.id}", admin, %{
        url: "https://hooks.example.test/escalated",
        events: ["ticket.created"],
        active: true
      })

      assert repo().get!(Webhook, webhook.id).secret == @webhook_secret
    end

    test "a new secret replaces the stored one, and clear_secret removes it", %{admin: admin} do
      webhook = webhook!()

      payload = %{
        url: "https://hooks.example.test/escalated",
        events: ["ticket.created"],
        active: true
      }

      request(:put, "#{@webhooks}/#{webhook.id}", admin, Map.put(payload, :secret, "whsec-new"))
      assert repo().get!(Webhook, webhook.id).secret == "whsec-new"

      request(
        :put,
        "#{@webhooks}/#{webhook.id}",
        admin,
        Map.merge(payload, %{secret: "", clear_secret: true})
      )

      assert repo().get!(Webhook, webhook.id).secret == nil
    end

    test "creating a webhook still stores the secret it is given", %{admin: admin} do
      request(:post, @webhooks, admin, %{
        url: "https://hooks.example.test/created",
        events: ["ticket.created"],
        secret: "whsec-created",
        active: true
      })

      assert repo().get_by!(Webhook, url: "https://hooks.example.test/created").secret ==
               "whsec-created"
    end
  end

  describe "settings" do
    test "the inbound email secret is host config and appears on no settings page",
         %{admin: admin} do
      Application.put_env(:escalated, :email_inbound_secret, "inb-9d8c7b6a5f4e")

      for path <- ["/support/admin/settings", "/support/admin/settings/email"] do
        conn = request(:get, path, admin)
        assert conn.status == 200
        refute_secrets(conn, ["inb-9d8c7b6a5f4e"])
      end
    end
  end

  describe "schemas" do
    test "every schema that stores a secret redacts it and has no JSON encoder" do
      webhook = webhook!()
      job = import_job!()

      two_factor = %TwoFactor{
        user_id: 1,
        secret: "TOTPSECRETBASE32XX",
        recovery_codes: ["rc-aaaa-bbbb"]
      }

      refute inspect(webhook) =~ @webhook_secret
      refute inspect(job) =~ job.credentials
      refute inspect(two_factor) =~ "TOTPSECRETBASE32XX"
      refute inspect(two_factor) =~ "rc-aaaa-bbbb"

      # A struct reaches a page only through its explicit serializer.
      for record <- [webhook, job, two_factor] do
        assert_raise Protocol.UndefinedError, fn -> Jason.encode!(record) end
      end

      refute Map.has_key?(Webhook.to_json(webhook), :secret)
      assert Webhook.to_json(webhook).has_secret == true

      refute Map.has_key?(
               Escalated.Controllers.Admin.ImportController.job_json(job),
               :credentials
             )
    end
  end
end
