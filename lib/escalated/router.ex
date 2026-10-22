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

  To embed the widget on other sites, mount the widget routes in a public
  pipeline of their own with `escalated_widget_routes/1`, running
  `Escalated.Plugs.WidgetCors` before `:protect_from_forgery`, and pass
  `widget: false` to `escalated_routes/2` (see
  `docs/embedding-the-widget.md`).
  """

  defmacro __using__(_opts) do
    quote do
      import Escalated.Router,
        only: [escalated_routes: 1, escalated_routes: 2, escalated_widget_routes: 1]
    end
  end

  @doc """
  Mounts only the widget routes (`{prefix}/widget/*`, including `embed.js`).

  Use it, with `escalated_routes(prefix, widget: false)`, to give the widget a
  pipeline of its own: one without the host's sign-in requirement, in which
  `Escalated.Plugs.WidgetCors` runs before `:protect_from_forgery` so sites
  listed in `widget_allowed_origins` can post without a CSRF token. See the
  README's router setup.
  """
  defmacro escalated_widget_routes(prefix), do: widget_scope(prefix)

  # Widget routes (public, rate-limited). Everything but /config and embed.js
  # is refused while the widget is disabled. WidgetCors runs first so CORS
  # headers reach every answer, rate-limit and tenant refusals included, and
  # so an embedded visitor is a guest before the tenant membership check.
  defp widget_scope(prefix) do
    quote do
      scope unquote(prefix), as: :escalated do
        scope "/widget", Escalated.Controllers, as: :widget do
          # The bundle is public and cacheable; it needs no tenant or session.
          get "/embed.js", WidgetScriptController, :show

          scope "/" do
            pipe_through [
              Escalated.Plugs.WidgetCors,
              Escalated.Plugs.ResolveTenant,
              Escalated.Plugs.TicketVisibility
            ]

            # CORS preflights are answered by WidgetCors before this action.
            options "/*path", WidgetController, :preflight

            scope "/" do
              pipe_through [Escalated.Plugs.WidgetRateLimit, Escalated.Plugs.GuestPrivacy]

              get "/config", WidgetController, :config
            end

            scope "/" do
              pipe_through [
                Escalated.Plugs.WidgetRateLimit,
                Escalated.Plugs.GuestPrivacy,
                Escalated.Plugs.EnsureWidgetEnabled
              ]

              post "/verification", GuestAccessController, :challenge
              post "/lookup", GuestAccessController, :lookup

              get "/tickets/:reference", WidgetController, :show_ticket

              # Knowledge-base search for the widget's help tab; it follows
              # the knowledge base's enabled and public settings.
              get "/articles", WidgetController, :search_articles
              get "/articles/:slug", WidgetController, :show_article

              # Writes get a per-IP limit of their own on top of the widget
              # budget (Escalated.Plugs.GuestSubmissionRateLimit). The reply
              # limit runs before the token is resolved, so wrong-token
              # guesses count.
              scope "/" do
                pipe_through Escalated.Plugs.GuestTicketRateLimit
                post "/tickets", WidgetController, :create_ticket
              end

              scope "/" do
                pipe_through Escalated.Plugs.GuestReplyRateLimit
                post "/tickets/:reference/reply", WidgetController, :reply
              end

              # Live chat widget routes (scope-relative; see the agent chat
              # routes).
              get "/chat/availability", WidgetChatController, :availability
              post "/chat/start", WidgetChatController, :start
              post "/chat/:token/end", WidgetChatController, :end_session
              post "/chat/:token/rate", WidgetChatController, :rate
              post "/chat/sessions/:reference/end", WidgetChatController, :end_session
            end

            # An open chat polls every three seconds and sends messages and
            # typing pings besides, so these routes have their own
            # per-capability budget.
            scope "/" do
              pipe_through [
                Escalated.Plugs.WidgetChatRateLimit,
                Escalated.Plugs.GuestPrivacy,
                Escalated.Plugs.EnsureWidgetEnabled
              ]

              get "/chat/:token/messages", WidgetChatController, :messages
              post "/chat/:token/messages", WidgetChatController, :send_message
              post "/chat/:token/typing", WidgetChatController, :typing
              post "/chat/sessions/:reference/messages", WidgetChatController, :send_message
            end
          end
        end
      end
    end
  end

  @doc """
  Mounts all Escalated routes under the given prefix.

  ## Options

    * `:ui` - whether to mount UI routes (default: value of `config :escalated, :ui_enabled`)
    * `:api` - whether to mount API routes (default: value of `config :escalated, :api_enabled`)
    * `:widget` - `false` leaves out the widget routes, for hosts that mount
      them with `escalated_widget_routes/1` (default: `true`)
  """
  defmacro escalated_routes(prefix, opts \\ []) do
    # `widget: false` leaves the widget routes to `escalated_widget_routes/1`,
    # mounted by the host in a pipeline of their own.
    widget = if Keyword.get(opts, :widget, true) == false, do: nil, else: widget_scope(prefix)

    quote do
      unquote(widget)

      scope unquote(prefix), as: :escalated do
        pipe_through [Escalated.Plugs.ResolveTenant, Escalated.Plugs.TicketVisibility]
        # Attachment downloads authenticate and authorize the owning ticket/reply.
        get "/attachments/:id/download", Escalated.Controllers.AttachmentController, :download

        # CSAT rating submission (customer by reference, guest by token).
        post "/tickets/:reference/rate",
             Escalated.Controllers.SatisfactionRatingController,
             :store

        scope "/guest" do
          pipe_through [Escalated.Plugs.GuestRateLimit, Escalated.Plugs.GuestPrivacy]

          post "/verification", Escalated.Controllers.GuestAccessController, :challenge
          post "/lookup", Escalated.Controllers.GuestAccessController, :lookup

          post "/tickets/:token/rate",
               Escalated.Controllers.SatisfactionRatingController,
               :store_guest

          # The guest portal pages (escalated.guest.tickets.*). /create is
          # declared ahead of /:token so it is never read as a token.
          get "/create", Escalated.Controllers.Guest.TicketController, :create
          get "/:token", Escalated.Controllers.Guest.TicketController, :show

          post "/:token/rate", Escalated.Controllers.SatisfactionRatingController, :store_guest,
            as: :guest_page_rate

          scope "/" do
            pipe_through Escalated.Plugs.GuestTicketRateLimit
            post "/", Escalated.Controllers.Guest.TicketController, :store
          end

          scope "/" do
            pipe_through Escalated.Plugs.GuestReplyRateLimit
            post "/:token/reply", Escalated.Controllers.Guest.TicketController, :reply
          end
        end

        # Customer routes
        scope "/", Escalated.Controllers.Customer do
          get "/tickets", TicketController, :index
          get "/tickets/new", TicketController, :new
          post "/tickets", TicketController, :create
          get "/tickets/:reference", TicketController, :show
          post "/tickets/:reference/reply", TicketController, :reply
          post "/tickets/:reference/close", TicketController, :close
          post "/tickets/:reference/reopen", TicketController, :reopen
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

          # The shared BulkActionBar (escalated.agent.tickets.bulk). Declared
          # ahead of the :reference routes; `alias: false` because the
          # controller is shared with the admin scope.
          post "/tickets/bulk", Escalated.Controllers.BulkActionController, :bulk, alias: false
          get "/tickets/:reference", TicketController, :show
          # escalated.agent.tickets.update: subject, description, custom_fields.
          put "/tickets/:reference", TicketController, :update
          patch "/tickets/:reference", TicketController, :update
          post "/tickets/:reference/reply", TicketController, :reply
          post "/tickets/:reference/note", TicketController, :note
          patch "/tickets/:reference/status", TicketController, :status
          patch "/tickets/:reference/priority", TicketController, :priority
          post "/tickets/:reference/assign", TicketController, :assign
          post "/tickets/:reference/actions/:action", TicketController, :custom_action
          # The shared ticket page posts these (escalated.agent.tickets.*). Status
          # and priority are POST there; the PATCH routes stay for API clients.
          post "/tickets/:reference/status", TicketController, :status
          post "/tickets/:reference/priority", TicketController, :priority
          post "/tickets/:reference/follow", TicketController, :follow
          post "/tickets/:reference/macro", TicketController, :macro
          post "/tickets/:reference/presence", TicketController, :presence
          post "/tickets/:reference/replies/:reply_id/pin", TicketController, :pin

          resources "/saved-views", SavedViewController, except: [:new, :edit]
          post "/tickets/:reference/snooze", TicketController, :snooze
          post "/tickets/:reference/unsnooze", TicketController, :unsnooze
          post "/tickets/:reference/split", TicketController, :split

          # Macro routes (agent-applied one-click action bundles).
          get "/macros", MacroController, :index
          post "/tickets/:ticket_id/macros/:macro_id/apply", MacroController, :apply

          # Canned responses visible to this agent (shared + their own).
          get "/canned-responses", CannedResponseController, :index

          # Live chat agent routes. Scope-relative like every other route here:
          # the scope already aliases Escalated.Controllers.Agent, so a fully
          # qualified name gets that prefix a second time and names nothing.
          get "/chat/sessions", ChatController, :sessions
          post "/chat/sessions/:id/accept", ChatController, :accept
          post "/chat/sessions/:id/message", ChatController, :send_message
          post "/chat/sessions/:id/end", ChatController, :end_session
        end

        # Admin routes
        scope "/admin", Escalated.Controllers.Admin, as: :admin do
          pipe_through Escalated.Plugs.EnsureAdmin

          get "/tickets", TicketController, :index

          # Ticket merge (the shared TicketMergeDialog) and bulk actions
          # (BulkActionBar). merge-search is declared ahead of
          # /tickets/:reference so the literal segment is never read as a
          # reference.
          get "/tickets/merge-search", TicketMergeController, :search
          post "/tickets/bulk", Escalated.Controllers.BulkActionController, :bulk, alias: false
          post "/tickets/:reference/merge", TicketMergeController, :merge
          get "/tickets/:reference", TicketController, :show
          post "/tickets/:reference/reply", TicketController, :reply
          post "/tickets/:reference/note", TicketController, :note
          patch "/tickets/:reference/status", TicketController, :status
          patch "/tickets/:reference/priority", TicketController, :priority
          post "/tickets/:reference/assign", TicketController, :assign
          patch "/tickets/:reference/tags", TicketController, :tags
          # The shared ticket page posts these (escalated.admin.tickets.*). Status
          # and priority are POST there; the PATCH routes stay for API clients.
          post "/tickets/:reference/status", TicketController, :status
          post "/tickets/:reference/priority", TicketController, :priority
          post "/tickets/:reference/follow", TicketController, :follow
          post "/tickets/:reference/macro", TicketController, :macro
          post "/tickets/:reference/presence", TicketController, :presence
          post "/tickets/:reference/replies/:reply_id/pin", TicketController, :pin
          post "/tickets/:reference/tags", TicketController, :tags
          post "/tickets/:reference/department", TicketController, :department
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

          # SLA policies (Laravel's resource routes: /create and /:id/edit).
          get "/sla-policies/create", SlaPolicyController, :new
          get "/sla-policies/:id/edit", SlaPolicyController, :edit

          resources "/sla-policies", SlaPolicyController,
            only: [:index, :create, :update, :delete]

          # Business hours (Laravel's resource routes: /create and /:id/edit).
          # Custom fields and custom objects (escalated.admin.custom-fields.*,
          # escalated.admin.custom-objects.*, Laravel's paths). The literal
          # segments are declared before the :id routes.
          get "/custom-fields/create", CustomFieldController, :new
          post "/custom-fields/reorder", CustomFieldController, :reorder
          get "/custom-fields/:id/edit", CustomFieldController, :edit

          resources "/custom-fields", CustomFieldController,
            only: [:index, :create, :update, :delete]

          # Custom ticket statuses (escalated.admin.statuses.*, Laravel's
          # paths).
          get "/statuses/create", StatusController, :new
          get "/statuses/:id/edit", StatusController, :edit

          resources "/statuses", StatusController, only: [:index, :create, :update, :delete]

          get "/custom-objects/create", CustomObjectController, :new
          get "/custom-objects/:id/edit", CustomObjectController, :edit
          get "/custom-objects/:id/records", CustomObjectController, :records
          post "/custom-objects/:id/records", CustomObjectController, :create_record
          put "/custom-objects/:id/records/:record_id", CustomObjectController, :update_record
          patch "/custom-objects/:id/records/:record_id", CustomObjectController, :update_record
          delete "/custom-objects/:id/records/:record_id", CustomObjectController, :delete_record

          resources "/custom-objects", CustomObjectController,
            only: [:index, :create, :update, :delete]

          get "/business-hours/create", BusinessHoursController, :new
          get "/business-hours/:id/edit", BusinessHoursController, :edit

          resources "/business-hours", BusinessHoursController,
            only: [:index, :create, :update, :delete]

          get "/audit-log", AuditLogController, :index

          # Report screens (escalated.admin.reports.*, Laravel's paths).
          get "/reports", ReportController, :index
          get "/reports/dashboard", ReportController, :dashboard
          get "/reports/agents", ReportController, :agents
          get "/reports/sla", ReportController, :sla
          get "/reports/csat", ReportController, :csat
          get "/reports/comparison", ReportController, :comparison
          get "/reports/frt", ReportController, :response_times
          get "/reports/response-times", ReportController, :response_times
          get "/reports/resolution", ReportController, :resolution_times
          get "/reports/resolution-times", ReportController, :resolution_times
          get "/reports/agent-ranking", ReportController, :agent_ranking
          get "/reports/sla-trends", ReportController, :sla_trends
          get "/reports/cohorts", ReportController, :cohorts

          resources "/departments", DepartmentController, except: [:edit]
          resources "/tags", TagController, except: [:edit]

          resources "/skills", SkillController, except: [:show]

          # Knowledge base admin (articles + categories).
          resources "/kb/categories", ArticleCategoryController, except: [:edit, :new, :show]
          resources "/kb/articles", ArticleController, except: [:edit, :new]

          # The shared pages' paths (escalated.admin.kb-articles.* and
          # kb-categories.*, Laravel's resource routes). The /kb/ paths above
          # stay for existing links.
          get "/kb-articles/create", ArticleController, :new
          get "/kb-articles/:id/edit", ArticleController, :edit
          resources "/kb-articles", ArticleController, only: [:index, :create, :update, :delete]

          resources "/kb-categories", ArticleCategoryController,
            only: [:index, :create, :update, :delete]

          # Users (host User model: list + grant/revoke admin/agent).
          # Surfaces the host's `users` table for an admin to flip the
          # `is_admin` / `is_agent` columns from the panel.
          get "/users", UserController, :index
          patch "/users/:user_id/role", UserController, :update_role

          # Roles and the permissions they grant (Laravel's resource routes).
          get "/roles/create", RoleController, :new
          get "/roles/:id/edit", RoleController, :edit
          resources "/roles", RoleController, only: [:index, :create, :update, :delete]

          # @mention autocomplete: matching agents by name/email.
          get "/agents/search", AgentSearchController, :search

          get "/settings", SettingsController, :index
          post "/settings", SettingsController, :update
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
          #
          # new/edit render the builder; toggle and reorder are the Index
          # page's controls. The wire shapes are fixed by
          # domain-model/workflow-admin-contract.md. reorder is declared ahead
          # of the resource so the literal segment is never read as an :id.
          post "/workflows/reorder", WorkflowController, :reorder
          # The run log, ahead of the resource so "logs" is never read as an id.
          get "/workflows/logs", WorkflowController, :logs
          get "/workflows/:id/logs", WorkflowController, :workflow_logs
          post "/workflows/:id/toggle", WorkflowController, :toggle
          resources "/workflows", WorkflowController

          # Time-based admin automations (distinct from event-driven Workflows
          # and agent-applied Macros — see escalated-developer-context).
          resources "/automations", AutomationController, except: [:edit, :new]
          post "/automations/run", AutomationController, :run

          # Time-based escalation rules (evaluated by
          # `mix escalated.evaluate_escalations`).
          # The shared pages link to /create and /:id/edit (Laravel's resource
          # routes); declared ahead of the resource so "create" is no id.
          get "/escalation-rules/create", EscalationRuleController, :new
          get "/escalation-rules/:id/edit", EscalationRuleController, :edit
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

          # Canned-response library admin CRUD (the agent-facing list lives
          # in the agent scope above).
          resources "/canned-responses", CannedResponseController, except: [:edit, :new]

          # Outbound webhooks: CRUD over subscriptions plus the per-webhook
          # delivery log and a manual delivery retry.
          get "/webhooks/create", WebhookController, :new
          get "/webhooks/:id/edit", WebhookController, :edit
          resources "/webhooks", WebhookController, only: [:index, :create, :update, :delete]
          post "/webhooks/deliveries/:id/retry", WebhookController, :retry
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
            scope "/kb" do
              pipe_through Escalated.Plugs.EnsureKbEnabled
              get "/articles", ResourceController, :kb_articles
              get "/categories", ResourceController, :kb_categories
            end

            get "/departments", ResourceController, :departments
            get "/tags", ResourceController, :tags

            # Anonymous (guest) ticket submission + lookup by token.
            scope "/guest" do
              pipe_through [Escalated.Plugs.GuestRateLimit, Escalated.Plugs.GuestPrivacy]

              post "/verification", GuestAccessController, :challenge
              post "/lookup", GuestAccessController, :lookup

              get "/tickets/:token", GuestTicketController, :show

              scope "/" do
                pipe_through Escalated.Plugs.GuestTicketRateLimit
                post "/tickets", GuestTicketController, :create
              end

              scope "/" do
                pipe_through Escalated.Plugs.GuestReplyRateLimit
                post "/tickets/:token/replies", GuestTicketController, :reply
              end
            end
          end

          # The ticket endpoints read and change any ticket, so they need a
          # known caller -- the host's current_user, or a bearer token the host
          # validates -- who passes agent_check. 401 without one, 403 for a
          # user who is not an agent. Laravel guards the same endpoints with
          # an agent token.
          scope "/api/v1", Escalated.Controllers.Api, as: :api do
            pipe_through [Escalated.Plugs.ApiAuthenticate, Escalated.Plugs.EnsureAgent]

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
