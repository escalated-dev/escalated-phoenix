defmodule Escalated.RoutePermissions do
  @moduledoc """
  The permission each admin, agent and staff API route requires while roles &
  permissions is switched on (ADR 2026-10-29-configurable-access-features).
  Ported from escalated-laravel's `RoutePermissions`.

  Phoenix routes have no names, so routes are keyed by `{controller, action}`.
  Each controller maps actions to slug lists; `:*` is the controller's
  fallback. A route that matches nothing is refused by
  `Escalated.Plugs.EnforceRoutePermissions`, and a test enumerates the router
  so a new route cannot ship without an entry here.

  Reads map to `*.view`, writes to `*.manage` (or the finer
  `create`/`edit`/`delete` slugs where they exist). Every slug is one
  `Escalated.Permissions.Catalog` seeds; none are invented here.
  """

  alias Escalated.Controllers.{Admin, Agent, Api}

  @closing_statuses ~w(resolved closed reopened)

  @bulk_actions %{
    "status" => ["ticket.edit"],
    "priority" => ["ticket.edit"],
    "assign" => ["ticket.assign"],
    "tags" => ["ticket.edit"],
    "department" => ["ticket.edit"],
    "delete" => ["ticket.delete"]
  }

  @doc "Statuses whose change needs `ticket.close` as well as `ticket.edit`."
  def closing_statuses, do: @closing_statuses

  @doc "Bulk actions and the permission each needs."
  def bulk_actions, do: @bulk_actions

  # index (and any extra read actions) => {group}.view; anything else => manage.
  defp resource(group, reads \\ [:index, :show]) do
    reads
    |> Map.new(&{&1, ["#{group}.view"]})
    |> Map.put(:*, ["#{group}.manage"])
  end

  defp settings_screen,
    do: %{index: ["settings.view"], *: ["settings.manage"]}

  @doc "`%{controller => %{action | :* => [slug]}}`."
  def map do
    view = ["ticket.view"]
    edit = ["ticket.edit"]

    agent_ticket = %{
      index: view,
      show: view,
      follow: view,
      presence: view,
      update: edit,
      status: edit,
      priority: edit,
      tags: edit,
      department: edit,
      pin: edit,
      custom_action: edit,
      snooze: edit,
      unsnooze: edit,
      split: ["ticket.create"],
      assign: ["ticket.assign"],
      macro: ["macro.view", "ticket.edit"],
      reply: ["reply.create"],
      note: ["reply.create_internal"]
    }

    newsletters = %{*: ["newsletters.manage"]}

    %{
      # ---- Tickets (admin and agent panels, staff API) ------------------
      Agent.DashboardController => %{index: view},
      Agent.TicketController => agent_ticket,
      Admin.TicketController => agent_ticket,
      # Bulk: per action, see required/2.
      Escalated.Controllers.BulkActionController => %{bulk: view},
      Admin.TicketMergeController => %{search: view, merge: ["ticket.merge"]},
      Admin.TicketSubjectController => %{*: edit},
      Admin.TicketLinkController => %{index: view, *: edit},
      Admin.SideConversationController => %{index: view, *: ["reply.create"]},
      Admin.AgentSearchController => %{search: view},
      Agent.SavedViewController => %{*: view},
      Agent.CannedResponseController => %{index: view},
      Agent.MacroController => %{index: ["macro.view"], apply: ["macro.view", "ticket.edit"]},
      Api.TicketController => %{
        index: view,
        show: view,
        create: ["ticket.create"],
        reply: ["reply.create"],
        status: edit,
        priority: edit,
        custom_action: edit,
        assign: ["ticket.assign"]
      },

      # ---- Live chat ------------------------------------------------------
      Agent.ChatController => %{sessions: view, *: ["reply.create"]},

      # ---- Reports ----------------------------------------------------------
      Admin.ReportController => %{*: ["report.view"]},

      # ---- Knowledge base ---------------------------------------------------
      Admin.ArticleController => %{
        index: ["kb.view"],
        show: ["kb.view"],
        new: ["kb.create"],
        create: ["kb.create"],
        edit: ["kb.edit"],
        update: ["kb.edit"],
        delete: ["kb.delete"]
      },
      Admin.ArticleCategoryController => %{
        index: ["kb.view"],
        create: ["kb.edit"],
        update: ["kb.edit"],
        delete: ["kb.delete"]
      },

      # ---- Departments ------------------------------------------------------
      Admin.DepartmentController => %{
        index: ["department.view"],
        show: ["department.view"],
        new: ["department.create"],
        create: ["department.create"],
        edit: ["department.edit"],
        update: ["department.edit"],
        delete: ["department.delete"]
      },

      # ---- Admin resources: reads => *.view, everything else => *.manage --
      Admin.SlaPolicyController => resource("sla"),
      Admin.BusinessHoursController => resource("sla"),
      Admin.EscalationRuleController => resource("escalation"),
      Admin.AutomationController => resource("automation"),
      Admin.WorkflowController => resource("automation", [:index, :show, :logs, :workflow_logs]),
      Admin.TagController => resource("tag"),
      Admin.CustomFieldController => resource("custom_field"),
      Admin.StatusController => resource("settings"),
      Admin.RoleController => resource("role"),
      Admin.SkillController => resource("user"),
      Admin.CapacityController => resource("user"),
      Admin.WebhookController => resource("webhook", [:index, :deliveries]),
      Admin.ApiTokenController => resource("api_token"),
      Admin.PluginController => resource("plugin"),
      Admin.CannedResponseController => resource("macro"),

      # Macros: anyone who may create one may save it; shared edits manage.
      Admin.MacroController => %{
        index: ["macro.view"],
        show: ["macro.view"],
        create: ["macro.create"],
        *: ["macro.manage"]
      },

      # Custom objects: schemas manage, records data.
      Admin.CustomObjectController => %{
        index: ["custom_object.view"],
        records: ["custom_object.view"],
        create_record: ["custom_object.data"],
        update_record: ["custom_object.data"],
        delete_record: ["custom_object.data"],
        *: ["custom_object.manage"]
      },

      # Users
      Admin.UserController => %{
        index: ["user.view"],
        update_role: ["user.manage"],
        update_roles: ["role.manage"]
      },
      Admin.AuditLogController => %{index: ["audit.view"]},

      # ---- Settings ---------------------------------------------------------
      Admin.SettingsController => %{
        index: ["settings.view"],
        public_tickets: ["settings.view"],
        *: ["settings.manage"]
      },
      Admin.CsatSettingsController => settings_screen(),
      Admin.DataRetentionController => settings_screen(),
      Admin.EmailSettingsController => settings_screen(),
      Admin.DatabaseConnectionController => settings_screen(),
      Admin.SsoSettingsController => settings_screen(),
      Admin.ImportController => %{*: ["settings.manage"]},

      # The signed-in user's own two-factor enrolment: every staff user, no
      # permission (ADR 2026-10-29, "personal screens").
      Admin.TwoFactorController => %{*: []},

      # ---- Newsletters (ADR 2026-05-19-newsletter-system) --------------------
      Admin.NewsletterController => newsletters,
      Admin.NewsletterListController => newsletters,
      Admin.NewsletterTemplateController => newsletters,
      Admin.NewsletterSettingsController => newsletters
    }
  end

  @doc "Whether `{controller, action}` has an entry."
  def mapped?(controller, action), do: lookup(controller, action) != nil

  @doc """
  The slugs a request to `controller`/`action` with `params` needs, or nil
  when the route is not mapped (the caller refuses it).

  Actions decided by the body are checked per action: a status change to
  `resolved`, `closed` or `reopened` also needs `ticket.close`, and a bulk
  action needs that action's permission.
  """
  def required(controller, action, params \\ %{}) do
    case lookup(controller, action) do
      nil -> nil
      slugs -> slugs |> add_body_checks(controller, params) |> Enum.uniq()
    end
  end

  defp add_body_checks(slugs, Escalated.Controllers.BulkActionController, params) do
    action = to_string(params["action"] || "")
    extra = Map.get(@bulk_actions, action, [])
    closing = if action == "status", do: closing(params["value"]), else: []
    slugs ++ extra ++ closing
  end

  defp add_body_checks(slugs, _controller, params) do
    if Map.has_key?(params, "status") and "ticket.edit" in slugs,
      do: slugs ++ closing(params["status"]),
      else: slugs
  end

  defp closing(status) when is_binary(status) and status in @closing_statuses,
    do: ["ticket.close"]

  defp closing(_), do: []

  defp lookup(controller, action) do
    case Map.get(map(), controller) do
      nil -> nil
      actions -> Map.get(actions, action) || Map.get(actions, :*)
    end
  end
end
