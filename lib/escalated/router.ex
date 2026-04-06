defmodule Escalated.Router do
  @moduledoc """
  Provides router macros for mounting Escalated routes in a Phoenix application.

  ## Usage

      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        use Escalated.Router

        scope "/" do
          pipe_through [:browser, :require_authenticated_user]
          escalated_routes("/support")
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import Escalated.Router, only: [escalated_routes: 1, escalated_routes: 2]
    end
  end

  @doc """
  Mounts all Escalated routes under the given prefix.

  ## Options

    * `:ui` - whether to mount UI routes (default: value of `config :escalated, :ui_enabled`)
    * `:api` - whether to mount API routes (default: value of `config :escalated, :api_enabled`)
  """
  defmacro escalated_routes(prefix, opts \\ []) do
    quote do
      scope unquote(prefix), as: :escalated do
        # Customer routes
        scope "/", Escalated.Controllers.Customer do
          get "/tickets", TicketController, :index
          get "/tickets/new", TicketController, :new
          post "/tickets", TicketController, :create
          get "/tickets/:reference", TicketController, :show
          post "/tickets/:reference/reply", TicketController, :reply
        end

        # Agent routes
        scope "/agent", Escalated.Controllers.Agent, as: :agent do
          pipe_through Escalated.Plugs.EnsureAgent

          get "/dashboard", DashboardController, :index
          get "/tickets", TicketController, :index
          get "/tickets/:reference", TicketController, :show
          post "/tickets/:reference/reply", TicketController, :reply
          post "/tickets/:reference/note", TicketController, :note
          patch "/tickets/:reference/status", TicketController, :status
          patch "/tickets/:reference/priority", TicketController, :priority
          post "/tickets/:reference/assign", TicketController, :assign
        end

        # Admin routes
        scope "/admin", Escalated.Controllers.Admin, as: :admin do
          pipe_through Escalated.Plugs.EnsureAdmin

          get "/tickets", TicketController, :index
          get "/tickets/:reference", TicketController, :show
          post "/tickets/:reference/reply", TicketController, :reply
          post "/tickets/:reference/note", TicketController, :note
          patch "/tickets/:reference/status", TicketController, :status
          patch "/tickets/:reference/priority", TicketController, :priority
          post "/tickets/:reference/assign", TicketController, :assign
          patch "/tickets/:reference/tags", TicketController, :tags
          patch "/tickets/:reference/department", TicketController, :department

          resources "/departments", DepartmentController, except: [:edit]
          resources "/tags", TagController, except: [:edit]
          get "/settings", SettingsController, :index
          put "/settings", SettingsController, :update
        end

        # API routes
        if unquote(opts[:api]) || Application.compile_env(:escalated, :api_enabled, false) do
          scope "/api/v1", Escalated.Controllers.Api, as: :api do
            post "/auth/validate", AuthController, :validate

            get "/tickets", TicketController, :index
            get "/tickets/:reference", TicketController, :show
            post "/tickets", TicketController, :create
            post "/tickets/:reference/reply", TicketController, :reply
            patch "/tickets/:reference/status", TicketController, :status
            patch "/tickets/:reference/priority", TicketController, :priority
            post "/tickets/:reference/assign", TicketController, :assign
          end
        end
      end
    end
  end
end
