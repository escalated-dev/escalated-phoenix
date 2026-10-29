defmodule Escalated.Permissions.Catalog do
  @moduledoc """
  Canonical Escalated permission definitions and the system roles, as
  escalated-laravel's `PermissionSeeder` seeds them. `Escalated.RoutePermissions`
  maps every staff route onto these slugs; none are invented there.
  """

  @groups [
    {"Tickets",
     [
       {"ticket.view", "View tickets", "View tickets"},
       {"ticket.create", "Create tickets", "Create tickets"},
       {"ticket.edit", "Edit ticket properties", "Edit ticket properties"},
       {"ticket.delete", "Delete tickets", "Delete tickets"},
       {"ticket.assign", "Assign tickets", "Assign tickets to agents"},
       {"ticket.merge", "Merge tickets", "Merge tickets together"},
       {"ticket.close", "Close tickets", "Close and reopen tickets"},
       {"ticket.export", "Export tickets", "Export ticket data"}
     ]},
    {"Replies",
     [
       {"reply.create", "Reply to tickets", "Reply to tickets"},
       {"reply.create_internal", "Add internal notes", "Add internal notes"},
       {"reply.edit", "Edit replies", "Edit replies"},
       {"reply.delete", "Delete replies", "Delete replies"}
     ]},
    {"Knowledge Base",
     [
       {"kb.view", "View knowledge base", "View knowledge base"},
       {"kb.create", "Create articles", "Create articles"},
       {"kb.edit", "Edit articles", "Edit articles"},
       {"kb.delete", "Delete articles", "Delete articles"},
       {"kb.publish", "Publish articles", "Publish/unpublish articles"}
     ]},
    {"Departments",
     [
       {"department.view", "View departments", "View departments"},
       {"department.create", "Create departments", "Create departments"},
       {"department.edit", "Edit departments", "Edit departments"},
       {"department.delete", "Delete departments", "Delete departments"}
     ]},
    {"Reports",
     [
       {"report.view", "View reports", "View reports and analytics"},
       {"report.export", "Export reports", "Export report data"}
     ]},
    {"SLA",
     [
       {"sla.view", "View SLA policies", "View SLA policies"},
       {"sla.manage", "Manage SLA policies", "Create, edit, delete SLA policies"}
     ]},
    {"Automations",
     [
       {"automation.view", "View automations", "View automations"},
       {"automation.manage", "Manage automations", "Create, edit, delete automations"}
     ]},
    {"Escalation Rules",
     [
       {"escalation.view", "View escalation rules", "View escalation rules"},
       {"escalation.manage", "Manage escalation rules", "Create, edit, delete escalation rules"}
     ]},
    {"Macros",
     [
       {"macro.view", "View macros", "View macros"},
       {"macro.create", "Create macros", "Create personal macros"},
       {"macro.manage", "Manage macros", "Create, edit, delete shared macros"}
     ]},
    {"Tags",
     [
       {"tag.view", "View tags", "View tags"},
       {"tag.manage", "Manage tags", "Create, edit, delete tags"}
     ]},
    {"Custom Fields",
     [
       {"custom_field.view", "View custom fields", "View custom fields"},
       {"custom_field.manage", "Manage custom fields", "Create, edit, delete custom fields"}
     ]},
    {"Roles",
     [
       {"role.view", "View roles", "View roles"},
       {"role.manage", "Manage roles", "Create, edit, delete roles and assign permissions"}
     ]},
    {"Users",
     [
       {"user.view", "View users", "View user profiles"},
       {"user.manage", "Manage users", "Manage user accounts and agent profiles"}
     ]},
    {"Settings",
     [
       {"settings.view", "View settings", "View settings"},
       {"settings.manage", "Manage settings", "Manage system settings"}
     ]},
    {"Webhooks",
     [
       {"webhook.view", "View webhooks", "View webhooks"},
       {"webhook.manage", "Manage webhooks", "Create, edit, delete webhooks"}
     ]},
    {"API Tokens",
     [
       {"api_token.view", "View API tokens", "View API tokens"},
       {"api_token.manage", "Manage API tokens", "Create, revoke API tokens"}
     ]},
    {"Audit Log", [{"audit.view", "View audit log", "View audit log"}]},
    {"Plugins",
     [
       {"plugin.view", "View plugins", "View plugins"},
       {"plugin.manage", "Manage plugins", "Install, configure, remove plugins"}
     ]},
    {"Custom Objects",
     [
       {"custom_object.view", "View custom objects", "View custom objects"},
       {"custom_object.manage", "Manage custom objects",
        "Create, edit, delete custom object schemas"},
       {"custom_object.data", "Manage custom object data", "Manage custom object records"}
     ]},
    {"Newsletters",
     [
       {"newsletters.manage", "Manage newsletters",
        "Create, edit, delete drafts and lists/templates; send test emails."},
       {"newsletters.send", "Send newsletters", "Schedule or send newsletters now."}
     ]}
  ]

  @all for {group, perms} <- @groups,
           {slug, name, description} <- perms,
           do: %{slug: slug, name: name, group: group, description: description}

  # System roles and the permissions they are seeded with. Patterns: "*" is
  # every permission, "ticket.*" every slug starting "ticket.".
  @roles [
    %{
      slug: "admin",
      name: "Admin",
      description: "Full access to all features and settings.",
      permissions: ["*"]
    },
    %{
      slug: "agent",
      name: "Agent",
      description: "Standard agent with ticket handling and limited administrative access.",
      permissions: ~w(ticket.* reply.* kb.view report.view macro.view macro.create tag.view
                      custom_field.view audit.view)
    },
    %{
      slug: "light_agent",
      name: "Light Agent",
      description: "Limited agent with read-only ticket access and internal note capability.",
      permissions: ~w(ticket.view reply.create reply.create_internal kb.view macro.view tag.view)
    }
  ]

  @doc "Every permission, as `%{slug, name, group, description}`."
  def all, do: @all

  @doc "Every permission slug."
  def slugs, do: Enum.map(@all, & &1.slug)

  @doc "The newsletter permissions."
  def newsletter, do: Enum.filter(@all, &(&1.group == "Newsletters"))

  @doc "The system roles: `%{slug, name, description, permissions}` (patterns)."
  def roles, do: @roles

  @doc "The permission slugs a list of patterns covers."
  def expand(patterns, slugs \\ slugs()) do
    Enum.flat_map(patterns, fn
      "*" ->
        slugs

      pattern ->
        if String.ends_with?(pattern, ".*") do
          prefix = String.trim_trailing(pattern, "*")
          Enum.filter(slugs, &String.starts_with?(&1, prefix))
        else
          Enum.filter(slugs, &(&1 == pattern))
        end
    end)
    |> Enum.uniq()
  end
end
