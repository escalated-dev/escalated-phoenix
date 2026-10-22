defmodule Escalated.PageCase do
  @moduledoc """
  Helpers for tests that render the shared Inertia pages through
  `Escalated.Test.Router`, the way a browser visit reaches them.

  A page test names the props the Vue page reads (nested keys too) and asserts
  every one of them is present. Asserting a status alone is how screens that
  render with no content shipped behind a green suite: Inertia answers 200 for
  a page whose props the component never looks at.

  The host's users live on `Escalated.HostTestRepo`, as `Escalated.Test.HostUser`
  rows, so names resolve the way they do in a host app.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use Escalated.DataCase, async: false

      import Plug.Conn
      import Plug.Test
      import Escalated.PageCase

      alias Escalated.Test.HostUser
    end
  end

  import Plug.Conn
  import Plug.Test
  import ExUnit.Assertions

  alias Ecto.Adapters.SQL.Sandbox
  alias Escalated.HostTestRepo
  alias Escalated.Test.{HostUser, Router}

  setup do
    :ok = Sandbox.checkout(HostTestRepo)
    Sandbox.mode(HostTestRepo, {:shared, self()})

    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :user_schema, HostUser)

    on_exit(fn ->
      Enum.each([:user_repo, :user_schema], &Application.delete_env(:escalated, &1))
      Sandbox.checkin(HostTestRepo)
    end)

    :ok
  end

  @doc "Inserts a host user and returns the map a host assigns as `current_user`."
  def host_user!(attrs) do
    user =
      HostTestRepo.insert!(
        struct(
          HostUser,
          Map.merge(
            %{name: "User", email: "user#{System.unique_integer([:positive])}@example.test"},
            attrs
          )
        )
      )

    %{
      id: user.id,
      name: user.name,
      email: user.email,
      is_admin: user.is_admin,
      is_agent: user.is_agent
    }
  end

  @doc """
  An Inertia visit through the router. `body` is sent as JSON, which is how
  Inertia's `router.post` and `useForm().post` send it.
  """
  def visit(method, path, user, body \\ nil) do
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
    |> then(fn conn -> if user, do: assign(conn, :current_user, user), else: conn end)
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> Router.call(Router.init([]))
  end

  @doc "The Inertia page object of a rendered response."
  def page!(conn, component) do
    assert conn.status == 200,
           "expected #{component} to render, got #{conn.status}: #{String.slice(conn.resp_body || "", 0, 500)}"

    page = Jason.decode!(conn.resp_body)
    assert page["component"] == component
    page["props"]
  end

  @doc "Asserts that `map` carries every key in `keys`."
  def assert_keys(map, keys, label \\ "props") do
    assert is_map(map), "#{label} is not a map: #{inspect(map)}"
    missing = Enum.reject(keys, &Map.has_key?(map, &1))
    assert missing == [], "#{label} is missing #{inspect(missing)}; has #{inspect(Map.keys(map))}"
    map
  end

  @doc "Asserts the Laravel length-aware paginator shape and returns its rows."
  def assert_paginator(value, label \\ "paginator") do
    assert_keys(
      value,
      ~w(data current_page last_page per_page total from to links),
      label
    )

    assert is_list(value["data"])
    value["data"]
  end

  def location(conn), do: conn |> get_resp_header("location") |> List.first()

  def inertia_version do
    conn(:get, "/")
    |> init_test_session(%{})
    |> Inertia.Plug.call(Inertia.Plug.init([]))
    |> Map.fetch!(:private)
    |> Map.fetch!(:inertia_version)
    |> to_string()
  end
end
