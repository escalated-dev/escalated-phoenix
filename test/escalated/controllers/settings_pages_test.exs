defmodule Escalated.Controllers.SettingsPagesTest do
  @moduledoc """
  The admin Settings sub-pages (`Escalated/Admin/Settings/*`) against the props
  the shared Vue pages read and the routes they post to (escalated-laravel's
  `CsatSettings`, `DataRetention`, `DatabaseConnection`, `EmailSettings` and
  `PublicTicketsSettings` controllers).
  """
  use Escalated.PageCase

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.SettingsService

  setup do
    %{admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})}
  end

  defp flash(conn, key), do: Phoenix.Flash.get(conn.assigns.flash, key)

  defp errors(conn) do
    assert conn.status in [302, 303], "expected a redirect with errors, got #{conn.status}"

    (conn |> Plug.Conn.fetch_session() |> Plug.Conn.get_session("inertia_errors") || %{})
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  defp redirected_to!(conn, path) do
    assert conn.status in [302, 303], "expected a redirect, got #{conn.status}: #{conn.resp_body}"
    assert location(conn) == path
    conn
  end

  defp refused?(conn), do: conn.status in [302, 303, 401, 403]

  describe "CsatSettings" do
    test "renders the defaults", %{admin: admin} do
      props =
        visit(:get, "/support/admin/settings/csat", admin)
        |> page!("Escalated/Admin/Settings/CsatSettings")

      assert props["settings"] == %{
               "csat_question_text" => "How would you rate your support experience?",
               "csat_scale" => "1-5",
               "csat_delivery_trigger" => "on_resolve",
               "csat_delay_hours" => 0
             }
    end

    test "saves and redirects back with a flash", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/csat", admin, %{
          "csat_question_text" => "How did we do?",
          "csat_scale" => "1-3",
          "csat_delivery_trigger" => "delayed",
          "csat_delay_hours" => 24
        })
        |> redirected_to!("/support/admin/settings/csat")

      assert flash(conn, :info) == "CSAT settings updated."
      assert SettingsService.get("csat_scale") == "1-3"
      assert SettingsService.get("csat_delay_hours") == "24"

      settings =
        visit(:get, "/support/admin/settings/csat", admin)
        |> page!("Escalated/Admin/Settings/CsatSettings")
        |> Map.fetch!("settings")

      assert settings["csat_question_text"] == "How did we do?"
      assert settings["csat_delivery_trigger"] == "delayed"
      assert settings["csat_delay_hours"] == 24
    end

    test "refuses an invalid scale and delay", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/csat", admin, %{
          "csat_question_text" => "Q",
          "csat_scale" => "1-10",
          "csat_delivery_trigger" => "on_resolve",
          "csat_delay_hours" => 500
        })

      assert conn.status in [302, 303]
      assert Map.has_key?(errors(conn), "csat_scale")
      assert Map.has_key?(errors(conn), "csat_delay_hours")
      assert SettingsService.get("csat_scale") == nil
    end
  end

  describe "DataRetention" do
    test "renders the settings and the purge preview", %{admin: admin} do
      props =
        visit(:get, "/support/admin/settings/data-retention", admin)
        |> page!("Escalated/Admin/Settings/DataRetention")

      assert props["settings"] == %{
               "retention_closed_tickets" => "never",
               "retention_attachments" => "never",
               "retention_audit_logs" => "never",
               "retention_user_data_gdpr" => false
             }

      assert props["purgePreview"] == %{"tickets" => 0, "attachments" => 0, "audit_logs" => 0}
    end

    test "the preview counts closed tickets past the cutoff", %{admin: admin} do
      SettingsService.set("retention_closed_tickets", "1_year", "retention")
      old = DateTime.utc_now() |> DateTime.add(-400 * 86_400) |> DateTime.truncate(:second)

      ticket!(%{status: "closed", closed_at: old})
      ticket!(%{status: "closed", closed_at: DateTime.truncate(DateTime.utc_now(), :second)})
      ticket!(%{status: "open"})

      props =
        visit(:get, "/support/admin/settings/data-retention", admin)
        |> page!("Escalated/Admin/Settings/DataRetention")

      assert props["purgePreview"]["tickets"] == 1
    end

    test "saves and redirects back with a flash", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/data-retention", admin, %{
          "retention_closed_tickets" => "2_years",
          "retention_attachments" => "1_year",
          "retention_audit_logs" => "90_days",
          "retention_user_data_gdpr" => true
        })
        |> redirected_to!("/support/admin/settings/data-retention")

      assert flash(conn, :info) == "Data retention settings updated."
      assert SettingsService.get("retention_closed_tickets") == "2_years"
      assert SettingsService.get("retention_user_data_gdpr") == "1"
    end

    test "an invalid option goes back with field errors on an Inertia visit", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/data-retention", admin, %{
          "retention_closed_tickets" => "forever",
          "retention_attachments" => "never",
          "retention_audit_logs" => "1_year",
          "retention_user_data_gdpr" => "maybe"
        })

      assert conn.status in [302, 303]

      assert Map.keys(errors(conn)) |> Enum.sort() ==
               ~w(retention_audit_logs retention_closed_tickets retention_user_data_gdpr)

      assert SettingsService.get("retention_closed_tickets") == nil
    end
  end

  describe "DatabaseConnection" do
    @connection_keys ~w(name driver database is_current is_host_default reachable migrated ticket_count error)

    test "describes the repo Escalated uses, read-only", %{admin: admin} do
      ticket!(%{})

      props =
        visit(:get, "/support/admin/settings/database", admin)
        |> page!("Escalated/Admin/Settings/DatabaseConnection")

      assert_keys(props, ~w(connections current hostDefault pinnedByConfig tablePrefix))
      assert [connection] = props["connections"]
      assert_keys(connection, @connection_keys, "connection")

      assert connection["name"] == "Escalated.TestRepo"
      assert props["current"] == "Escalated.TestRepo"
      assert props["hostDefault"] == "Escalated.TestRepo"
      assert props["pinnedByConfig"] == true
      assert props["tablePrefix"] == Application.get_env(:escalated, :table_prefix)

      assert connection["is_current"] == true
      assert connection["is_host_default"] == true
      assert connection["reachable"] == true
      assert connection["migrated"] == true
      assert connection["ticket_count"] == 1
      assert connection["error"] == nil
      assert connection["driver"] in ~w(sqlite postgres mysql)
      assert is_binary(connection["database"])
      refute connection["database"] =~ "password"
    end

    test "update is refused because the connection is set in configuration", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/database", admin, %{"connection" => "Other"})
        |> redirected_to!("/support/admin/settings/database")

      assert flash(conn, :error) ==
               "The database connection is set in configuration and cannot be changed from here."
    end

    test "test describes a known connection as JSON", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/database/test", admin, %{
          "connection" => "Escalated.TestRepo"
        })

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert_keys(body, @connection_keys, "connection")
      assert body["reachable"] == true
    end

    test "test refuses an unknown or missing connection", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/database/test", admin, %{"connection" => "Nope"})

      assert conn.status in [302, 303]
      assert Map.has_key?(errors(conn), "connection")

      conn = visit(:post, "/support/admin/settings/database/test", admin, %{})
      assert Map.has_key?(errors(conn), "connection")
    end
  end

  describe "EmailSettings" do
    test "renders empty defaults", %{admin: admin} do
      props =
        visit(:get, "/support/admin/settings/email", admin)
        |> page!("Escalated/Admin/Settings/EmailSettings")

      assert props["addresses"] == []
      assert props["defaultReplyAddress"] == ""
    end

    test "saves the addresses normalised and the default reply address", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/email", admin, %{
          "addresses" => [
            %{
              "email" => "support@example.test",
              "display_name" => "Support",
              "department_id" => 3,
              "dkim_status" => "verified",
              "extra" => "dropped"
            },
            %{"email" => "billing@example.test"}
          ],
          "default_reply_address" => "noreply@example.test"
        })
        |> redirected_to!("/support/admin/settings/email")

      assert flash(conn, :info) == "Email settings updated."

      props =
        visit(:get, "/support/admin/settings/email", admin)
        |> page!("Escalated/Admin/Settings/EmailSettings")

      assert props["addresses"] == [
               %{
                 "email" => "support@example.test",
                 "display_name" => "Support",
                 "department_id" => 3,
                 "dkim_status" => "verified"
               },
               %{
                 "email" => "billing@example.test",
                 "display_name" => nil,
                 "department_id" => nil,
                 "dkim_status" => "unknown"
               }
             ]

      assert props["defaultReplyAddress"] == "noreply@example.test"
    end

    test "refuses an invalid address", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/email", admin, %{
          "addresses" => [%{"email" => "not-an-email", "dkim_status" => "great"}],
          "default_reply_address" => "also bad"
        })

      assert conn.status in [302, 303]
      keys = Map.keys(errors(conn))
      assert "addresses.0.email" in keys
      assert "addresses.0.dkim_status" in keys
      assert "default_reply_address" in keys
      assert SettingsService.get("email_addresses") == nil
    end
  end

  describe "PublicTickets" do
    test "renders the guest policy", %{admin: admin} do
      props =
        visit(:get, "/support/admin/settings/public-tickets", admin)
        |> page!("Escalated/Admin/Settings/PublicTickets")

      assert props["settings"] == %{
               "guest_policy_mode" => "unassigned",
               "guest_policy_user_id" => nil,
               "guest_policy_signup_url_template" => ""
             }
    end

    test "POST (the shared page) saves and redirects with a flash", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/public-tickets", admin, %{
          "guest_policy_mode" => "guest_user",
          "guest_policy_user_id" => 7,
          "guest_policy_signup_url_template" => "ignored"
        })
        |> redirected_to!("/support/admin/settings/public-tickets")

      assert flash(conn, :info) == "Guest policy updated."
      assert SettingsService.get("guest_policy_user_id") == "7"
      assert SettingsService.get_or_default("guest_policy_signup_url_template", "x") == "x"

      settings =
        visit(:get, "/support/admin/settings/public-tickets", admin)
        |> page!("Escalated/Admin/Settings/PublicTickets")
        |> Map.fetch!("settings")

      assert settings["guest_policy_mode"] == "guest_user"
      assert settings["guest_policy_user_id"] == "7"
    end

    test "PUT is accepted too", %{admin: admin} do
      visit(:put, "/support/admin/settings/public-tickets", admin, %{
        "guest_policy_mode" => "prompt_signup",
        "guest_policy_signup_url_template" => "https://example.test/join?email={email}"
      })
      |> redirected_to!("/support/admin/settings/public-tickets")

      assert SettingsService.get("guest_policy_mode") == "prompt_signup"

      assert SettingsService.get("guest_policy_signup_url_template") ==
               "https://example.test/join?email={email}"
    end

    test "guest_user needs a user id; an unknown mode is refused", %{admin: admin} do
      conn =
        visit(:post, "/support/admin/settings/public-tickets", admin, %{
          "guest_policy_mode" => "guest_user"
        })

      assert Map.has_key?(errors(conn), "guest_policy_user_id")

      conn =
        visit(:post, "/support/admin/settings/public-tickets", admin, %{
          "guest_policy_mode" => "anything"
        })

      assert Map.has_key?(errors(conn), "guest_policy_mode")
      assert SettingsService.get("guest_policy_mode") == nil
    end

    test "a JSON client keeps the JSON answer" do
      admin = host_user!(%{name: "Api Admin", is_admin: true, is_agent: true})

      conn =
        conn(:get, "/support/admin/settings/public-tickets")
        |> init_test_session(%{})
        |> assign(:current_user, admin)
        |> put_req_header("accept", "application/json")
        |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["guest_policy_mode"] == "unassigned"
    end
  end

  test "non-admins are turned away from every settings page" do
    agent = host_user!(%{name: "Agent", is_admin: false, is_agent: true})

    for path <- ~w(csat data-retention database email public-tickets) do
      assert refused?(visit(:get, "/support/admin/settings/#{path}", agent)), path
    end

    assert refused?(
             visit(:post, "/support/admin/settings/email", agent, %{
               "addresses" => [%{"email" => "x@example.test"}]
             })
           )

    assert SettingsService.get("email_addresses") == nil
  end

  defp ticket!(attrs) do
    {status, attrs} = Map.pop(attrs, :status)
    {closed_at, attrs} = Map.pop(attrs, :closed_at)

    ticket =
      %Ticket{}
      |> Ticket.changeset(Map.merge(%{subject: "S", description: "d"}, attrs))
      |> Escalated.repo().insert!()

    ticket
    |> Ecto.Changeset.change(%{status: status || ticket.status, closed_at: closed_at})
    |> Escalated.repo().update!()
  end
end
