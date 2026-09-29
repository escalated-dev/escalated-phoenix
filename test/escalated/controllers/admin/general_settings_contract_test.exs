defmodule Escalated.Controllers.Admin.GeneralSettingsContractTest do
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Plugs.ShareInertiaData
  alias Escalated.Schemas.{Article, EscalatedSetting}
  alias Escalated.Services.{GeneralSettings, SettingsService}
  alias Escalated.Test.Router

  @path "/support/admin/settings"
  @admin %{id: 1, is_admin: true}

  setup do
    keys = [
      :admin_check,
      :route_prefix | Enum.map(GeneralSettings.supported_keys(), &String.to_existing_atom/1)
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Enum.each(keys, &Application.delete_env(:escalated, &1))

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "renders the existing page with exactly the supported typed settings and POST URL" do
    page = visit(:get, @path) |> page()
    assert page["component"] == "Escalated/Admin/Settings"
    assert page["props"]["supported_settings"] == GeneralSettings.supported_keys()
    assert page["props"]["update_url"] == @path

    assert page["props"]["settings"] == %{
             "knowledge_base_enabled" => false,
             "knowledge_base_public" => false,
             "knowledge_base_feedback_enabled" => false,
             "show_powered_by" => true
           }
  end

  test "flat POST and legacy nested PUT persist without changing application config" do
    conn = visit(:post, @path, %{"knowledge_base_enabled" => true, "show_powered_by" => false})
    assert conn.status in [302, 303]
    assert get_resp_header(conn, "location") == [@path]
    assert Application.fetch_env(:escalated, :knowledge_base_enabled) == :error
    assert page(visit(:get, @path))["props"]["settings"]["knowledge_base_enabled"]
    row = Escalated.repo().get_by!(EscalatedSetting, key: "show_powered_by")
    assert {row.value, row.type, row.group} == {"0", "boolean", "general"}

    conn = visit(:put, @path, %{"settings" => %{"knowledge_base_enabled" => "false"}})
    assert conn.status == 303
    refute GeneralSettings.enabled?(:knowledge_base_enabled)
    assert Escalated.repo().aggregate(EscalatedSetting, :count) == 2
  end

  test "unknown fields and invalid values reject the whole update and retain field errors" do
    {:ok, _} = GeneralSettings.update(%{"show_powered_by" => true})

    conn =
      visit(:post, @path, %{
        "show_powered_by" => false,
        "knowledge_base_public" => "sometimes",
        "imap_password" => "unimplemented"
      })

    assert conn.status in [302, 303]
    errors = get_session(conn, "inertia_errors")
    assert errors["knowledge_base_public"] == "Must be a boolean."
    assert errors["imap_password"] == "This setting is not supported."
    assert GeneralSettings.enabled?(:show_powered_by)
    assert Escalated.repo().aggregate(EscalatedSetting, :count) == 1
    assert conn.assigns.flash[:info] == nil
    assert visit(:post, @path, %{"settings" => []}).status in [302, 303]
  end

  test "non-Inertia validation returns JSON 422 and admin authorization precedes reads and writes" do
    conn = visit(:post, @path, %{"show_powered_by" => %{}}, @admin, false)
    assert conn.status == 422
    assert Jason.decode!(conn.resp_body)["errors"]["show_powered_by"] == "Must be a boolean."

    for user <- [nil, %{id: 2, is_admin: false}], method <- [:get, :post, :put] do
      conn = visit(method, @path, %{"show_powered_by" => false}, user)
      assert conn.status in [302, 401, 403]
      assert Escalated.repo().all(EscalatedSetting) == []
    end
  end

  test "database overrides explicit config and remains visible in a fresh caller" do
    Application.put_env(:escalated, :knowledge_base_enabled, "true")
    assert GeneralSettings.enabled?(:knowledge_base_enabled)
    {:ok, _} = GeneralSettings.update(%{"knowledge_base_enabled" => "0"})
    Application.put_env(:escalated, :knowledge_base_enabled, true)
    refute Task.async(fn -> GeneralSettings.enabled?(:knowledge_base_enabled) end) |> Task.await()

    {:ok, _} = SettingsService.set("knowledge_base_enabled", "corrupt", "general")
    assert GeneralSettings.enabled?(:knowledge_base_enabled)
  end

  test "only active admin profiles grant admin access and explicit callback denial wins" do
    alias Escalated.Schemas.AgentProfile

    profile =
      %AgentProfile{}
      |> AgentProfile.changeset(%{user_id: 20, role: "admin", is_active: true})
      |> Escalated.repo().insert!()

    assert visit(:get, @path, nil, %{id: 20}).status == 200
    profile |> AgentProfile.changeset(%{is_active: false}) |> Escalated.repo().update!()
    assert visit(:get, @path, nil, %{id: 20}).status == 403

    for result <- [false, "false", :error] do
      Application.put_env(:escalated, :admin_check, fn _ -> result end)
      assert visit(:post, @path, %{"show_powered_by" => false}).status == 403
    end

    assert Escalated.repo().all(EscalatedSetting) == []
  end

  test "API knowledge-base endpoints enforce the same persisted access preferences" do
    article!()

    for path <- ["/support/api/v1/kb/articles", "/support/api/v1/kb/categories"] do
      assert visit(:get, path, nil, nil, false).status == 404
    end

    {:ok, _} = GeneralSettings.update(%{"knowledge_base_enabled" => true})
    assert visit(:get, "/support/api/v1/kb/articles", nil, nil, false).status == 404
    assert visit(:get, "/support/api/v1/kb/articles", nil, %{id: 2}, false).status == 200
    {:ok, _} = GeneralSettings.update(%{"knowledge_base_public" => true})
    assert visit(:get, "/support/api/v1/kb/articles", nil, nil, false).status == 200
    assert visit(:get, "/support/api/v1/kb/categories", nil, nil, false).status == 200
  end

  test "persisted branding is shared with the application footer" do
    {:ok, _} = GeneralSettings.update(%{"show_powered_by" => false})
    refute ShareInertiaData.escalated_props(nil, Escalated.configuration()).show_powered_by
  end

  test "persisted KB enable/public gates prevent anonymous reads and feedback writes" do
    article = article!()
    {:ok, _} = GeneralSettings.update(%{"knowledge_base_enabled" => true})
    assert visit(:get, "/support/kb/#{article.slug}", nil, nil).status == 404

    assert visit(:post, "/support/kb/#{article.slug}/feedback", %{"helpful" => true}, nil).status ==
             404

    assert Escalated.repo().reload!(article).view_count == 0
    assert Escalated.repo().reload!(article).helpful_count == 0
    assert visit(:get, "/support/kb/#{article.slug}", nil, %{id: 2}).status == 200

    {:ok, _} = GeneralSettings.update(%{"knowledge_base_public" => true})
    assert visit(:get, "/support/kb/#{article.slug}", nil, nil).status == 200
    {:ok, _} = GeneralSettings.update(%{"knowledge_base_enabled" => false})
    assert visit(:get, "/support/kb", nil, @admin).status == 404

    assert visit(:post, "/support/kb/#{article.slug}/feedback", %{"helpful" => true}, @admin).status ==
             404
  end

  test "persisted feedback preference governs page props and direct POST writes" do
    article = article!()

    {:ok, _} =
      GeneralSettings.update(%{"knowledge_base_enabled" => true, "knowledge_base_public" => true})

    refute page(visit(:get, "/support/kb/#{article.slug}", nil, nil))["props"]["feedback_enabled"]

    assert visit(:post, "/support/kb/#{article.slug}/feedback", %{"helpful" => true}, nil).status ==
             404

    assert Escalated.repo().reload!(article).helpful_count == 0
    {:ok, _} = GeneralSettings.update(%{"knowledge_base_feedback_enabled" => true})
    assert page(visit(:get, "/support/kb/#{article.slug}", nil, nil))["props"]["feedback_enabled"]

    assert visit(:post, "/support/kb/#{article.slug}/feedback", %{"helpful" => true}, nil).status ==
             200

    assert Escalated.repo().reload!(article).helpful_count == 1
  end

  test "settings URL follows a custom configured route prefix" do
    Application.put_env(:escalated, :route_prefix, "/help/")
    assert page(visit(:get, @path))["props"]["update_url"] == "/help/admin/settings"
  end

  defp article! do
    %Article{}
    |> Article.changeset(%{title: "Parcel", body: "Support", status: "published"})
    |> Escalated.repo().insert!()
  end

  defp visit(method, path, body \\ nil, user \\ @admin, inertia? \\ true) do
    conn =
      conn(method, path, if(is_nil(body), do: nil, else: Jason.encode!(body)))
      |> put_req_header("content-type", "application/json")
      |> init_test_session(%{})
      |> assign(:current_user, user)

    conn =
      if inertia? do
        version =
          conn |> Inertia.Plug.call([]) |> Map.fetch!(:private) |> Map.fetch!(:inertia_version)

        conn
        |> put_req_header("x-inertia", "true")
        |> put_req_header("x-inertia-version", to_string(version))
      else
        conn
      end

    Router.call(conn, Router.init([]))
  end

  defp page(conn) do
    assert conn.status == 200
    Jason.decode!(conn.resp_body)
  end
end
