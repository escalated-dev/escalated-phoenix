defmodule Escalated.UserContractTest do
  @moduledoc """
  A host that has not set up its users gets an error naming what to configure,
  not a raw `UndefinedFunctionError` / `Protocol.UndefinedError`, when a staff
  action first resolves a user; `mix escalated.doctor` reports the same
  problems, and missing staff gates, up front.
  """
  use Escalated.PageCase

  alias Escalated.UserContract

  defmodule NotASchema do
    @moduledoc false
    defstruct [:id, :name, :email]
  end

  defmodule NoGateUser do
    @moduledoc false
    use Ecto.Schema

    schema "users" do
      field(:name, :string)
      field(:email, :string)
    end
  end

  setup do
    keys = [:agent_check, :admin_check]
    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    Enum.each(keys, &Application.delete_env(:escalated, &1))
    :ok
  end

  describe "the user schema" do
    test "a schema that is not an Ecto schema raises a clear error on a staff page" do
      Application.put_env(:escalated, :user_schema, NotASchema)
      agent = host_user!(%{name: "Al Agent", is_agent: true})

      error = staff_error(fn -> visit(:get, "/support/agent/tickets", agent) end)

      assert error.message =~ "Escalated.UserContractTest.NotASchema is not an Ecto schema"
      assert error.message =~ "config :escalated, user_schema:"
      assert error.message =~ "use Ecto.Schema"
    end

    test "an unset schema names the config key" do
      Application.delete_env(:escalated, :user_schema)

      error = assert_raise UserContract.Error, fn -> Escalated.user_schema() end
      assert error.message =~ "config :escalated, :user_schema is not set"
    end

    test "a configured Ecto schema with :id passes" do
      assert Escalated.user_schema() == Escalated.Test.HostUser
    end
  end

  describe "the signed-in user on staff routes" do
    test "a current_user without :id raises a clear error instead of a bare 403" do
      for path <- ["/support/agent/tickets", "/support/admin/settings"] do
        error =
          staff_error(fn ->
            visit(:get, path, %{email: "staff@example.test", is_admin: true})
          end)

        assert error.message =~ "conn.assigns.current_user"
        assert error.message =~ "has no :id field"
      end
    end

    test "a current_user that is not a map raises without echoing it" do
      error = staff_error(fn -> visit(:get, "/support/agent/tickets", "staff@example.test") end)

      assert error.message =~ "must be your user struct or a map with :id"
      refute error.message =~ "staff@example.test"
    end

    test "no signed-in user is still a 401, and a non-staff user still a 403" do
      assert visit(:get, "/support/agent/tickets", nil).status == 401

      customer = host_user!(%{name: "Cy Customer"})
      assert visit(:get, "/support/agent/tickets", customer).status == 403
    end
  end

  describe "problems/0 (mix escalated.doctor)" do
    test "a correctly set up install has none" do
      assert UserContract.problems() == []
    end

    test "reports a schema that breaks the contract as an error" do
      Application.put_env(:escalated, :user_schema, NotASchema)

      assert [{:error, message} | _] = UserContract.problems()
      assert message =~ "is not an Ecto schema"
    end

    test "reports missing staff gates as a warning" do
      Application.put_env(:escalated, :user_schema, NoGateUser)

      assert [{:warning, message}] = UserContract.problems()
      assert message =~ "no staff gate"
      assert message =~ "agent_check"

      Application.put_env(:escalated, :agent_check, fn _user -> true end)
      assert UserContract.problems() == []
    end

    test "the doctor task prints the problems and fails on an error" do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      Application.put_env(:escalated, :user_schema, NotASchema)

      assert_raise Mix.Error, ~r/setup problems found/, fn ->
        Mix.Tasks.Escalated.Doctor.run([])
      end

      assert_received {:mix_shell, :info, ["[error] " <> message]}
      assert message =~ "is not an Ecto schema"
      assert_received {:mix_shell, :info, ["[warning] " <> scheduler]}
      assert scheduler =~ "mix escalated.check_sla"
    end
  end

  # The router wraps what a plug raises in Plug.Conn.WrapperError.
  defp staff_error(fun) do
    fun.()
    flunk("expected Escalated.UserContract.Error")
  rescue
    error in Plug.Conn.WrapperError ->
      assert %UserContract.Error{} = error.reason
      error.reason
  end
end
