defmodule Escalated.Controllers.ImportPagesTest do
  @moduledoc """
  The admin Import wizard the shared frontend drives
  (src/pages/Admin/Import/{Index,Connect,Mapping,Review,Progress}.vue), on
  escalated-laravel's routes and props (`Admin\\ImportController`,
  `ImportService`, `ImportJob`, `ImportContext`).

  The source is `Escalated.Test.FakeImportAdapter`, registered on the
  `"import.adapters"` filter the way a host or plugin registers a Zendesk or
  Freshdesk adapter. Runs go through the default task runner.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Import.{Context, Credentials, Runner}
  alias Escalated.Schemas.{Contact, ImportJob, ImportSourceMap, Reply, SlaPolicy, Ticket}
  alias Escalated.Services.{AutomationRunner, EscalationService, SlaService}
  alias Escalated.Test.FakeImportAdapter, as: Fake

  @base "/support/admin/import"
  @field_mappings %{"tickets" => %{"subject" => "title", "state" => "status"}}
  @shared ~w(errors auth current_user flash escalated plugin_ui page)
  @manifest "test/fixtures/escalated-pages.json"
            |> File.read!()
            |> Jason.decode!()

  defp repo, do: Escalated.repo()

  setup do
    previous = Map.new([:filters, :import_secret], &{&1, Application.get_env(:escalated, &1)})

    Application.put_env(:escalated, :filters, %{
      "import.adapters" => [fn adapters -> adapters ++ [Fake] end]
    })

    Application.put_env(:escalated, :import_secret, String.duplicate("import-secret-", 4))
    Application.put_env(:escalated, :fake_import_listener, self())

    on_exit(fn ->
      Runner.await_all()

      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:escalated, key)
        {key, value} -> Application.put_env(:escalated, key, value)
      end)

      Enum.each(
        [:fake_import_listener, :fake_import_on_extract],
        &Application.delete_env(:escalated, &1)
      )
    end)

    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})
    ada = host_user!(%{name: "Ada Customer", email: "ada@customer.test"})
    %{admin: admin, ada: ada}
  end

  # A visit that carries the session from the previous one, as a browser does.
  defp request(method, path, user, body, session) do
    base =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    base
    |> init_test_session(session)
    |> assign(:current_user, user)
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
  end

  defp session_of(conn), do: Plug.Conn.get_session(conn)

  defp connect!(admin, credentials \\ Fake.credentials()) do
    request(:post, "#{@base}/fakedesk/test-connection", admin, %{credentials: credentials}, %{})
  end

  defp start!(admin) do
    connected = connect!(admin)
    assert Jason.decode!(connected.resp_body) == %{"success" => true}

    conn =
      request(
        :post,
        "#{@base}/fakedesk/start",
        admin,
        %{field_mappings: @field_mappings},
        session_of(connected)
      )

    Runner.await_all()
    job = repo().one!(from(j in ImportJob, order_by: [desc: j.inserted_at], limit: 1))
    {conn, job}
  end

  defp screen!(conn, component, except \\ []) do
    props = page!(conn, component)
    declared = @manifest["props"][component]["props"] -- except
    sent = Map.keys(props) -- @shared
    assert Enum.sort(sent) == Enum.sort(declared), "#{component} props"
    props
  end

  defp job!(status) do
    %ImportJob{}
    |> ImportJob.changeset(%{
      platform: "fakedesk",
      status: status,
      credentials: Credentials.seal(Fake.credentials())
    })
    |> repo().insert!()
  end

  defp running_job! do
    %ImportJob{}
    |> ImportJob.changeset(%{
      platform: "fakedesk",
      status: "importing",
      credentials: Credentials.seal(Fake.credentials()),
      field_mappings: @field_mappings,
      progress: %{
        "tickets" => %{
          "total" => 3,
          "processed" => 1,
          "skipped" => 0,
          "failed" => 1,
          "cursor" => "2"
        }
      },
      error_log: [
        %{"entity_type" => "tickets", "source_id" => "k9", "error" => "boom", "timestamp" => "x"}
      ]
    })
    |> repo().insert!()
  end

  defp imported_tickets(job) do
    ids =
      repo().all(
        from(m in ImportSourceMap,
          where: m.import_job_id == ^job.id and m.entity_type == "tickets",
          order_by: m.id,
          select: m.escalated_id
        )
      )
      |> Enum.map(&String.to_integer/1)

    repo().all(from(t in Ticket, where: t.id in ^ids, order_by: t.id, preload: :tags))
  end

  defp reload(job), do: repo().get!(ImportJob, job.id)

  defp drain_extracts(acc \\ []) do
    receive do
      {:extract, type, cursor, importing?} -> drain_extracts([{type, cursor, importing?} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  describe "Index" do
    test "lists the registered adapters and the recent jobs", %{admin: admin} do
      job = job!("completed")

      props = request(:get, @base, admin, nil, %{}) |> screen!("Escalated/Admin/Import/Index")

      assert props["adapters"] == [
               %{
                 "name" => "fakedesk",
                 "display_name" => "FakeDesk",
                 "credential_fields" => Fake.credential_fields_json()
               }
             ]

      [row] = props["jobs"]
      assert row["id"] == job.id
      assert row["platform"] == "fakedesk"
      assert row["status"] == "completed"
      assert row["created_at"]
      refute Map.has_key?(row, "credentials")
    end

    test "is admin only" do
      agent = host_user!(%{name: "Al Agent", is_agent: true})

      conn = request(:get, @base, agent, nil, %{})

      assert conn.status in [302, 403]
    end
  end

  describe "Connect" do
    test "renders the credential form", %{admin: admin} do
      props =
        request(:get, "#{@base}/fakedesk/connect", admin, nil, %{})
        |> screen!("Escalated/Admin/Import/Connect")

      assert props["platform"] == "fakedesk"
      assert props["display_name"] == "FakeDesk"
      assert props["credential_fields"] == Fake.credential_fields_json()
    end

    test "is a 404 for a platform no adapter provides", %{admin: admin} do
      assert request(:get, "#{@base}/nowhere/connect", admin, nil, %{}).status == 404
    end

    test "test-connection answers success false for refused credentials", %{admin: admin} do
      conn = connect!(admin, Map.put(Fake.credentials(), "api_token", "wrong"))

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"success" => false}
    end

    test "test-connection answers 422 with the error when the source raises", %{admin: admin} do
      conn = connect!(admin, Map.put(Fake.credentials(), "subdomain", "down"))

      assert conn.status == 422

      assert Jason.decode!(conn.resp_body) == %{
               "success" => false,
               "error" => "FakeDesk is unreachable"
             }
    end
  end

  describe "Mapping" do
    test "sends the visitor back to Connect until a connection is tested", %{admin: admin} do
      conn = request(:get, "#{@base}/fakedesk/mapping", admin, nil, %{})

      assert conn.status in [302, 303]
      assert get_resp_header(conn, "location") == ["#{@base}/fakedesk/connect"]
    end

    test "renders defaults and source fields read with the stored credentials", %{admin: admin} do
      session = admin |> connect!() |> session_of()

      conn = request(:get, "#{@base}/fakedesk/mapping", admin, nil, session)
      # Laravel does not send the declared `credentials` either: they stay on the server.
      props = screen!(conn, "Escalated/Admin/Import/Mapping", ["credentials"])

      assert props["entity_types"] == ~w(contacts tags tickets replies)

      assert props["mappings"]["tickets"] == %{
               "defaults" => %{"subject" => "title", "state" => "status"},
               "source_fields" => Fake.ticket_source_fields()
             }

      assert props["mappings"]["contacts"] == %{"defaults" => %{}, "source_fields" => []}
      assert_received {:source_fields, credentials}
      assert credentials == Fake.credentials()
      refute conn.resp_body =~ Fake.token()
    end
  end

  describe "Review" do
    test "echoes the choices and writes nothing", %{admin: admin} do
      props =
        request(
          :post,
          "#{@base}/fakedesk/review",
          admin,
          %{field_mappings: @field_mappings, entity_types: ["tickets", "replies"]},
          %{}
        )
        |> page!("Escalated/Admin/Import/Review")

      assert props["platform"] == "fakedesk"
      assert props["field_mappings"] == @field_mappings
      assert props["entity_types"] == ["tickets", "replies"]
      assert repo().aggregate(ImportJob, :count) == 0
    end
  end

  describe "start" do
    test "refuses without a tested connection", %{admin: admin} do
      conn =
        request(:post, "#{@base}/fakedesk/start", admin, %{field_mappings: @field_mappings}, %{})

      assert get_resp_header(conn, "location") == ["#{@base}/fakedesk/connect"]
      assert repo().aggregate(ImportJob, :count) == 0
    end

    test "creates the job and imports the tickets end to end in import mode", %{
      admin: admin,
      ada: ada
    } do
      sla_policy =
        %SlaPolicy{}
        |> SlaPolicy.changeset(%{
          name: "Default",
          is_default: true,
          is_active: true,
          first_response_hours: %{"high" => 1, "urgent" => 1, "medium" => 4},
          resolution_hours: %{"high" => 8, "urgent" => 8, "medium" => 24}
        })
        |> repo().insert!()

      {conn, job} = start!(admin)

      assert get_resp_header(conn, "location") == ["#{@base}/progress/#{job.id}"]
      assert job.user_id == admin.id
      assert job.field_mappings == @field_mappings
      assert job.status == "completed"
      assert job.completed_at
      assert job.credentials == nil
      assert job.error_log == []

      assert job.progress["tickets"] == %{
               "total" => 3,
               "processed" => 3,
               "skipped" => 0,
               "failed" => 0,
               "cursor" => "2"
             }

      tickets = imported_tickets(job)
      assert Enum.map(tickets, & &1.subject) == ["Refund please", "Login broken", "Feature idea"]
      assert Enum.map(tickets, & &1.status) == ["open", "resolved", "open"]
      assert Enum.map(tickets, & &1.priority) == ["high", "urgent", "medium"]

      [refund, login, _] = tickets
      # Ada is a host user; Bob becomes an Escalated contact on a guest ticket.
      assert refund.requester_id == ada.id
      assert login.guest_email == "bob@customer.test"
      assert login.contact_id == repo().get_by!(Contact, email: "bob@customer.test").id
      assert Enum.map(refund.tags, & &1.name) == ["Billing"]
      assert refund.inserted_at == ~U[2024-01-02 03:04:05Z]
      assert repo().aggregate(from(r in Reply, where: r.is_internal == true), :count) == 1
      assert repo().aggregate(Reply, :count) == 2

      # Import mode in the run only, and no SLA clock on imported history.
      extracts = drain_extracts()
      assert extracts != []
      assert Enum.all?(extracts, fn {_, _, importing?} -> importing? end)
      refute Context.importing?()
      assert Enum.all?(tickets, &is_nil(&1.sla_policy_id))
      assert sla_policy.id
    end

    test "keeps the credentials sealed at rest", %{admin: admin} do
      Application.put_env(:escalated, :fake_import_on_extract, fn _, _ -> raise "source down" end)

      {_conn, job} = start!(admin)

      stored =
        repo().one!(
          from(j in "#{Escalated.config(:table_prefix, "escalated_")}import_jobs",
            select: j.credentials
          )
        )

      refute stored =~ Fake.token()
      assert job.status == "failed"
    end
  end

  describe "Progress and status" do
    test "renders the job the screen polls", %{admin: admin} do
      job = running_job!()

      conn = request(:get, "#{@base}/progress/#{job.id}", admin, nil, %{})
      sent = screen!(conn, "Escalated/Admin/Import/Progress")["job"]

      assert sent["id"] == job.id
      assert sent["status"] == "importing"
      assert sent["progress"] == job.progress
      assert sent["error_log"] == job.error_log
      assert sent["field_mappings"] == @field_mappings
      refute Map.has_key?(sent, "credentials")
      refute conn.resp_body =~ Fake.token()
    end

    test "status answers the poll", %{admin: admin} do
      job = running_job!()

      body = Jason.decode!(request(:get, "#{@base}/status/#{job.id}", admin, nil, %{}).resp_body)

      assert Enum.sort(Map.keys(body)) ==
               Enum.sort(~w(status progress error_log started_at completed_at))

      assert body["status"] == "importing"
      assert body["progress"] == job.progress
      assert body["error_log"] == job.error_log
    end

    test "status is a 404 for an unknown job", %{admin: admin} do
      assert request(:get, "#{@base}/status/nope", admin, nil, %{}).status == 404
    end
  end

  describe "pause, resume and cancel" do
    test "pauses mid-run and resumes without importing anything twice", %{admin: admin} do
      Application.put_env(:escalated, :fake_import_on_extract, fn
        "tickets", "2" -> repo().update_all(ImportJob, set: [status: "paused"])
        _, _ -> :ok
      end)

      {_conn, job} = start!(admin)

      assert job.status == "paused"
      assert length(imported_tickets(job)) == 3
      refute Map.has_key?(job.progress, "replies")
      assert job.credentials

      Application.delete_env(:escalated, :fake_import_on_extract)
      drain_extracts()

      conn = request(:post, "#{@base}/resume/#{job.id}", admin, %{}, %{})
      Runner.await_all()

      assert get_resp_header(conn, "location") == ["#{@base}/progress/#{job.id}"]
      job = reload(job)
      assert job.status == "completed"
      assert length(imported_tickets(job)) == 3
      assert repo().aggregate(Reply, :count) == 2

      # The run picked tickets up from its saved cursor, not from the start.
      calls = Enum.map(drain_extracts(), fn {type, cursor, _} -> {type, cursor} end)
      refute {"tickets", nil} in calls
      assert {"tickets", "2"} in calls
    end

    test "pause stops an importing job", %{admin: admin} do
      job = running_job!()

      conn = request(:post, "#{@base}/pause/#{job.id}", admin, %{}, %{})

      assert get_resp_header(conn, "location") == ["#{@base}/progress/#{job.id}"]
      assert reload(job).status == "paused"
    end

    test "resume runs a failed job again through mapping", %{admin: admin} do
      job = job!("failed")

      request(:post, "#{@base}/resume/#{job.id}", admin, %{}, %{})
      Runner.await_all()

      job = reload(job)
      assert job.status == "completed"
      assert length(imported_tickets(job)) == 3
    end

    test "cancel stops a job for good and drops its credentials", %{admin: admin} do
      job = job!("paused")

      conn = request(:post, "#{@base}/cancel/#{job.id}", admin, %{}, %{})

      assert get_resp_header(conn, "location") == ["#{@base}/progress/#{job.id}"]
      job = reload(job)
      assert job.status == "failed"
      assert job.completed_at
      assert job.credentials == nil
    end
  end

  describe "import mode" do
    test "holds back SLA attachment, escalations and automations" do
      %SlaPolicy{}
      |> SlaPolicy.changeset(%{
        name: "Default",
        is_default: true,
        is_active: true,
        first_response_hours: %{"medium" => 4},
        resolution_hours: %{"medium" => 24}
      })
      |> repo().insert!()

      ticket =
        %Ticket{}
        |> Ticket.changeset(%{subject: "Old", description: "Old"})
        |> repo().insert!()

      results =
        Context.suppress(fn ->
          {:ok, _} = SlaService.attach_policy(ticket)
          {EscalationService.evaluate_rules(repo()), AutomationRunner.run(repo())}
        end)

      assert results == {0, 0}
      assert repo().get!(Ticket, ticket.id).sla_policy_id == nil
      refute Context.importing?()
    end
  end
end
