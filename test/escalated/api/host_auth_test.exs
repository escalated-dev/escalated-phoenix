defmodule Escalated.Api.HostAuthTest do
  use Escalated.DataCase, async: false

  alias Escalated.Api.HostAuth

  @keys [
    :api_authenticator,
    :api_registrar,
    :api_token_refresher,
    :api_token_validator,
    :api_profile_updater,
    :api_logout
  ]

  setup do
    on_exit(fn -> Enum.each(@keys, &Application.delete_env(:escalated, &1)) end)
    :ok
  end

  test "the auth controller is compiled" do
    assert Code.ensure_loaded?(Escalated.Controllers.Api.AuthController)
  end

  test "authenticate delegates to the configured host callback" do
    Application.put_env(:escalated, :api_authenticator, fn %{"email" => email} ->
      {:ok, %{token: "abc", user: %{email: email}}}
    end)

    assert {:ok, %{token: "abc", user: %{email: "a@b.com"}}} =
             HostAuth.authenticate(%{"email" => "a@b.com"})
  end

  test "register and refresh and profile delegate to their callbacks" do
    Application.put_env(:escalated, :api_registrar, fn _ -> {:ok, %{token: "new"}} end)
    Application.put_env(:escalated, :api_token_refresher, fn _ -> {:ok, %{token: "fresh"}} end)
    Application.put_env(:escalated, :api_profile_updater, fn _token, attrs -> {:ok, attrs} end)

    assert {:ok, %{token: "new"}} = HostAuth.register(%{})
    assert {:ok, %{token: "fresh"}} = HostAuth.refresh("old")
    assert {:ok, %{name: "Pat"}} = HostAuth.update_profile("tok", %{name: "Pat"})
  end

  test "an unconfigured callback yields :not_configured" do
    assert :not_configured = HostAuth.authenticate(%{})
    assert :not_configured = HostAuth.refresh("tok")
  end

  test "callback errors map to client/auth failures" do
    Application.put_env(:escalated, :api_authenticator, fn _ -> {:error, :bad_credentials} end)
    assert {:error, "bad_credentials"} = HostAuth.authenticate(%{})

    Application.put_env(:escalated, :api_authenticator, fn _ -> :error end)
    assert :unauthorized = HostAuth.authenticate(%{})
  end

  test "logout is a best-effort no-op when unconfigured" do
    assert :ok = HostAuth.logout("token")
    assert :ok = HostAuth.logout(nil)
  end

  test "logout invokes the configured callback" do
    parent = self()

    Application.put_env(:escalated, :api_logout, fn token ->
      send(parent, {:logged_out, token})
    end)

    assert :ok = HostAuth.logout("tok-123")
    assert_received {:logged_out, "tok-123"}
  end
end
