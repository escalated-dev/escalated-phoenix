defmodule Escalated.Test.RouteTable do
  @moduledoc false

  # Phoenix's `__routes__/0` leaves out the pipelines each route runs, which is
  # what a host's middleware is in Phoenix. A test router that adds
  # `@before_compile Escalated.Test.RouteTable` gets `__route_table__/0`: every
  # route with its verb, path, controller, action, helper and pipe_through.

  defmacro __before_compile__(env) do
    table =
      env.module
      |> Module.get_attribute(:phoenix_routes)
      |> Enum.reverse()
      |> Enum.map(fn route ->
        %{
          verb: route.verb,
          path: route.path,
          plug: route.plug,
          plug_opts: route.plug_opts,
          helper: route.helper,
          pipe_through: route.pipe_through
        }
      end)

    quote do
      @doc false
      def __route_table__, do: unquote(Macro.escape(table))
    end
  end
end
