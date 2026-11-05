defmodule Escalated.Embed.DefaultUnchangedTest do
  @moduledoc """
  Embedding the admin in the host's admin panel is optional and off by default
  (ADR 2026-11-05-embeddable-admin). With no `config :escalated, :ui, embed:`
  the route table a host mounts must be exactly what it was before the
  feature existed.

  `test/fixtures/embed/default-routes.json` was generated from the code before
  embedding was added: every route `escalated_routes/2` mounts (verb, path,
  controller, action, helper and the pipelines it runs), and the named route
  table the shared frontend calls (`Escalated.Routes`, its stand-in for route
  names). Regenerate it only for a deliberate route change:

      ESCALATED_WRITE_ROUTE_SNAPSHOT=1 mix test test/escalated/embed/default_unchanged_test.exs
  """
  use ExUnit.Case, async: false

  alias Escalated.Test.Router

  @fixture Path.expand("../../fixtures/embed/default-routes.json", __DIR__)

  @doc false
  def snapshot do
    routes =
      Router.__route_table__()
      |> Enum.map(fn route ->
        %{
          "verb" => route.verb |> to_string() |> String.upcase(),
          "path" => route.path,
          "controller" => inspect(route.plug),
          "action" => inspect(route.plug_opts),
          "helper" => route.helper,
          "pipe_through" => Enum.map(route.pipe_through, &inspect/1)
        }
      end)
      |> Enum.sort_by(&{&1["path"], &1["verb"], &1["action"]})

    names =
      "/support"
      |> Escalated.Routes.routes()
      |> Enum.map(fn {name, route} ->
        %{"name" => name, "uri" => route.uri, "methods" => route.methods}
      end)
      |> Enum.sort_by(& &1["name"])

    %{"routes" => routes, "names" => names}
  end

  test "the route table and the named routes match the snapshot taken before embedding" do
    current = snapshot()

    if System.get_env("ESCALATED_WRITE_ROUTE_SNAPSHOT") == "1" do
      File.mkdir_p!(Path.dirname(@fixture))
      File.write!(@fixture, Jason.encode_to_iodata!(current, pretty: true))
    end

    expected = @fixture |> File.read!() |> Jason.decode!()

    assert length(current["routes"]) == length(expected["routes"])
    assert current["routes"] -- expected["routes"] == []
    assert expected["routes"] -- current["routes"] == []
    assert current["names"] == expected["names"]
  end
end
