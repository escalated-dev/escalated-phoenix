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
        # Attachment downloads (accessible to any authenticated user)
        get "/attachments/:id/download", Escalated.Controllers.AttachmentController, :download

        # CSAT rating submission (customer by reference, guest by token).
        post "/tickets/:reference/rate",
             Escalated.Controllers.SatisfactionRatingController,
             :store

        post "/guest/tickets/:token/rate",
             Escalated.Controllers.SatisfactionRatingController,
             :store_guest

        # Customer routes
        scope "/", Escalated.Controllers.Customer do
          get "/tickets", TicketController, :index
          get "/tickets/new", TicketController, :new
          post "/tickets", TicketController, :create
          get "/tickets/:reference", TicketController, :show
          post "/tickets/:reference/reply", TicketController, :reply
        end

        # Customer-facing knowledge base (read + feedback), gated by the
        # knowledge_base_enabled config via EnsureKbEnabled.
        scope "/kb", Escalated.Controllers.Customer, as: :kb do
          pipe_through Escalated.Plugs.EnsureKbEnabled

          get "/", KnowledgeBaseController, :index
          get "/:slug", KnowledgeBaseController, :show
          post "/:slug/feedback", KnowledgeBaseController, :feedback
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
          post "/tickets/:reference/actions/:action", TicketController, :custom_action

          resources "/saved-views", SavedViewController, except: [:new, :edit]
          post "/tickets/:reference/snooze", TicketController, :snooze
          post "/tickets/:reference/unsnooze", TicketController, :unsnooze
          post "/tickets/:reference/split", TicketController, :split

          # Macro routes (agent-applied one-click action bundles).
          get "/macros", MacroController, :index
          post "/tickets/:ticket_id/macros/:macro_id/apply", MacroController, :apply

          # Live chat agent routes
          get "/chat/sessions", Escalated.Controllers.Agent.ChatController, :sessions
          post "/chat/sessions/:id/accept", Escalated.Controllers.Agent.ChatController, :accept

          post "/chat/sessions/:id/message",
               Escalated.Controllers.Agent.ChatController,
               :send_message

          post "/chat/sessions/:id/end", Escalated.Controllers.Agent.ChatController, :end_session
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
          post "/tickets/:reference/subjects", TicketSubjectController, :create
          delete "/tickets/:reference/subjects/:id", TicketSubjectController, :delete

          # Typed ticket-to-ticket links (problem/incident, parent/child, related).
          get "/tickets/:reference/links", TicketLinkController, :index
          post "/tickets/:reference/links", TicketLinkController, :create
          delete "/tickets/:reference/links/:id", TicketLinkController, :delete

          # Side conversations (internal-note / email side-channel threads).
          get "/tickets/:reference/side-conversations", SideConversationController, :index
          post "/tickets/:reference/side-conversations", SideConversationController, :create

          post "/tickets/:reference/side-conversations/:id/reply",
               SideConversationController,
               :reply

          post "/tickets/:reference/side-conversations/:id/close",
               SideConversationController,
               :close

          patch "/tickets/:reference/department", TicketController, :department
          post "/tickets/:reference/snooze", TicketController, :snooze
          post "/tickets/:reference/unsnooze", TicketController, :unsnooze
          post "/tickets/:reference/split", TicketController, :split

          resources "/departments", DepartmentController, except: [:edit]
          resources "/tags", TagController, except: [:edit]

          resources "/skills", SkillController, except: [:show]

          # Knowledge base admin (articles + categories).
          resources "/kb/categories", ArticleCategoryController, except: [:edit, :new, :show]
          resources "/kb/articles", ArticleController, except: [:edit, :new]

          # Users (host User model: list + grant/revoke admin/agent).
          # Surfaces the host's `users` table for an admin to flip the
          # `is_admin` / `is_agent` columns from the panel.
          get "/users", UserController, :index
          patch "/users/:user_id/role", UserController, :update_role

          get "/settings", SettingsController, :index
          put "/settings", SettingsController, :update

          # CSAT settings (question text, scale, delivery trigger, delay).
          get "/settings/csat", CsatSettingsController, :index
          post "/settings/csat", CsatSettingsController, :update

          # Data retention settings + purge preview.
          get "/settings/data-retention", DataRetentionController, :index
          post "/settings/data-retention", DataRetentionController, :update

          # Event-driven admin Workflows (fired inline from TicketService on
          # ticket lifecycle events — distinct from time-based Automations
          # and agent-applied Macros; see escalated-developer-context).
          resources "/workflows", WorkflowController, except: [:edit, :new]

          # Time-based admin automations (distinct from event-driven Workflows
          # and agent-applied Macros — see escalated-developer-context).
          resources "/automations", AutomationController, except: [:edit, :new]
          post "/automations/run", AutomationController, :run

          # Time-based escalation rules (evaluated by
          # `mix escalated.evaluate_escalations`).
          resources "/escalation-rules", EscalationRuleController, except: [:edit, :new]
          post "/escalation-rules/run", EscalationRuleController, :run

          # Per-agent ticket capacity (load-aware assignment).
          get "/capacity", CapacityController, :index
          patch "/capacity/:id", CapacityController, :update

          # Plugins / extensibility (activate/deactivate host-registered
          # plugin modules; the hook dispatch itself lives in
          # Escalated.Plugins.Hooks).
          get "/plugins", PluginController, :index
          post "/plugins/:slug/activate", PluginController, :activate
          post "/plugins/:slug/deactivate", PluginController, :deactivate
          delete "/plugins/:slug", PluginController, :delete

          # Macro admin CRUD (the agent-facing apply endpoint lives in
          # the agent scope above).
          resources "/macros", MacroController, except: [:edit, :new]

          # Outbound webhooks: CRUD over subscriptions plus the per-webhook
          # delivery log and a manual delivery retry.
          resources "/webhooks", WebhookController, only: [:index, :create, :update, :delete]
          get "/webhooks/:id/deliveries", WebhookController, :deliveries
          post "/webhook-deliveries/:id/retry", WebhookController, :retry

          get "/settings/public-tickets", SettingsController, :public_tickets
          put "/settings/public-tickets", SettingsController, :update_public_tickets

          if Application.compile_env(:escalated, :enable_newsletters, false) do
            # Newsletter admin (static paths before :newsletter catch-all)
            get "/newsletters", NewsletterController, :index
            get "/newsletters/new", NewsletterController, :create
            post "/newsletters", NewsletterController, :store
            post "/newsletters/preview", NewsletterController, :preview
            post "/newsletters/test", NewsletterController, :test_send

            get "/newsletters/lists", NewsletterListController, :index
            get "/newsletters/lists/new", NewsletterListController, :create
            post "/newsletters/lists", NewsletterListController, :store
            get "/newsletters/lists/:list", NewsletterListController, :show
            put "/newsletters/lists/:list", NewsletterListController, :update
            delete "/newsletters/lists/:list", NewsletterListController, :delete
            post "/newsletters/lists/:list/members", NewsletterListController, :add_member

            delete "/newsletters/lists/:list/members/:contact_id",
                   NewsletterListController,
                   :remove_member

            post "/newsletters/lists/:list/import", NewsletterListController, :import_csv

            get "/newsletters/templates", NewsletterTemplateController, :index
            get "/newsletters/templates/new", NewsletterTemplateController, :create
            post "/newsletters/templates", NewsletterTemplateController, :store
            get "/newsletters/templates/:template", NewsletterTemplateController, :show
            put "/newsletters/templates/:template", NewsletterTemplateController, :update
            delete "/newsletters/templates/:template", NewsletterTemplateController, :delete

            get "/newsletters/settings", NewsletterSettingsController, :show
            put "/newsletters/settings", NewsletterSettingsController, :update

            get "/newsletters/:newsletter", NewsletterController, :show
            get "/newsletters/:newsletter/edit", NewsletterController, :edit
            put "/newsletters/:newsletter", NewsletterController, :update
            delete "/newsletters/:newsletter", NewsletterController, :delete
          end
        end

        if Application.compile_env(:escalated, :enable_newsletters, false) do
          scope "/escalated", Escalated.Controllers.Public, as: :newsletter_public do
            pipe_through Escalated.Plugs.EnsureNewslettersEnabled

            get "/n/o/:token", NewsletterTrackingController, :open
            get "/n/c/:token", NewsletterTrackingController, :click
            get "/n/u/:token", NewsletterTrackingController, :unsubscribe_show
            post "/n/u/:token", NewsletterTrackingController, :unsubscribe_store
            get "/n/v/:token", NewsletterTrackingController, :view
          end

          scope "/escalated/webhooks/newsletter", Escalated.Controllers.Webhooks,
            as: :newsletter_webhooks do
            pipe_through Escalated.Plugs.EnsureNewslettersEnabled

            post "/postmark", NewsletterEspWebhookController, :postmark
            post "/mailgun", NewsletterEspWebhookController, :mailgun
            post "/ses", NewsletterEspWebhookController, :ses
            post "/sendgrid", NewsletterEspWebhookController, :sendgrid
          end
        end

        # Widget routes (public, rate-limited)
        scope "/widget", Escalated.Controllers, as: :widget do
          pipe_through Escalated.Plugs.WidgetRateLimit

          get "/config", WidgetController, :config
          post "/tickets", WidgetController, :create_ticket
          get "/tickets/:reference", WidgetController, :show_ticket
          post "/tickets/:reference/reply", WidgetController, :reply

          # Live chat widget routes
          get "/chat/availability", Escalated.Controllers.WidgetChatController, :availability
          post "/chat/start", Escalated.Controllers.WidgetChatController, :start

          post "/chat/sessions/:reference/messages",
               Escalated.Controllers.WidgetChatController,
               :send_message

          post "/chat/sessions/:reference/end",
               Escalated.Controllers.WidgetChatController,
               :end_session
        end

        # API routes
        if unquote(opts[:api]) || Application.compile_env(:escalated, :api_enabled, false) do
          scope "/api/v1", Escalated.Controllers.Api, as: :api do
            post "/auth/login", AuthController, :login
            post "/auth/register", AuthController, :register
            post "/auth/logout", AuthController, :logout
            post "/auth/refresh", AuthController, :refresh
            get "/auth/me", AuthController, :me
            patch "/auth/profile", AuthController, :profile
            post "/auth/validate", AuthController, :validate

            # Public reference endpoints (Flutter app / integrations).
            get "/kb/articles", ResourceController, :kb_articles
            get "/kb/categories", ResourceController, :kb_categories
            get "/departments", ResourceController, :departments
            get "/tags", ResourceController, :tags

            # Anonymous (guest) ticket submission + lookup by token.
            post "/guest/tickets", GuestTicketController, :create
            get "/guest/tickets/:token", GuestTicketController, :show

            get "/tickets", TicketController, :index
            get "/tickets/:reference", TicketController, :show
            post "/tickets", TicketController, :create
            post "/tickets/:reference/reply", TicketController, :reply
            patch "/tickets/:reference/status", TicketController, :status
            patch "/tickets/:reference/priority", TicketController, :priority
            post "/tickets/:reference/assign", TicketController, :assign
            post "/tickets/:reference/actions/:action", TicketController, :custom_action
          end
        end
      end
    end
  end
end
