defmodule Escalated.Tenancy.Tables do
  @moduledoc """
  Explicit ownership and reference registry for Escalated's merchant data.

  Names are unprefixed; callers must use `Escalated.table_name/1`. Unknown
  tables are not implicitly safe. `unique_keys` lists tenant-local keys, not
  globally unique ticket references or newsletter tracking capabilities.

  Polymorphic references require type-aware validation. They are deliberately
  separate from ordinary host user references; an entity ID is not a user ID.
  Host reference lists contain host user IDs. JSON workflow/action references
  must also be checked when interpreted by their domain services.
  """

  @entries [
    %{
      name: "guest_challenges",
      schema: Escalated.Schemas.GuestChallenge,
      local_refs: %{},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "guest_grants",
      schema: Escalated.Schemas.GuestGrant,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [],
      unique_keys: [[:ticket_id, :purpose]]
    },
    %{
      name: "agent_capacity",
      schema: Escalated.Schemas.AgentCapacity,
      local_refs: %{},
      host_refs: [:user_id],
      unique_keys: [[:user_id, :channel]]
    },
    %{
      name: "agent_profiles",
      schema: Escalated.Schemas.AgentProfile,
      local_refs: %{},
      host_refs: [:user_id],
      unique_keys: [[:user_id]]
    },
    %{
      name: "agent_skills",
      schema: Escalated.Schemas.AgentSkill,
      local_refs: %{skill_id: {"skills", :id}},
      host_refs: [:user_id],
      unique_keys: [[:user_id, :skill_id]]
    },
    %{
      name: "article_categories",
      schema: Escalated.Schemas.ArticleCategory,
      local_refs: %{parent_id: {"article_categories", :id}},
      host_refs: [],
      unique_keys: [[:slug]]
    },
    %{
      name: "articles",
      schema: Escalated.Schemas.Article,
      local_refs: %{category_id: {"article_categories", :id}},
      host_refs: [:author_id],
      unique_keys: [[:slug]]
    },
    %{
      name: "attachments",
      schema: Escalated.Schemas.Attachment,
      local_refs: %{reply_id: {"replies", :id}, ticket_id: {"tickets", :id}},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "audit_logs",
      schema: Escalated.Schemas.AuditLog,
      local_refs: %{},
      host_refs: [],
      unique_keys: [],
      polymorphic_refs: %{entity_id: :entity_type, performer_id: :performer_type}
    },
    %{
      name: "automations",
      schema: Escalated.Schemas.Automation,
      local_refs: %{},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "business_schedules",
      schema: Escalated.Schemas.BusinessSchedule,
      local_refs: %{},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "canned_responses",
      schema: Escalated.Schemas.CannedResponse,
      local_refs: %{},
      host_refs: [:created_by],
      unique_keys: []
    },
    %{
      name: "chat_routing_rules",
      schema: Escalated.Schemas.ChatRoutingRule,
      local_refs: %{department_id: {"departments", :id}},
      host_refs: [],
      unique_keys: [],
      host_ref_lists: [:agent_ids]
    },
    %{
      name: "chat_sessions",
      schema: Escalated.Schemas.ChatSession,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [:agent_id],
      unique_keys: []
    },
    %{
      name: "contacts",
      schema: Escalated.Schemas.Contact,
      local_refs: %{},
      host_refs: [:user_id],
      unique_keys: [[:email]]
    },
    %{
      name: "custom_field_values",
      schema: Escalated.Schemas.CustomFieldValue,
      local_refs: %{custom_field_id: {"custom_fields", :id}},
      host_refs: [],
      unique_keys: [[:custom_field_id, :entity_type, :entity_id]],
      polymorphic_refs: %{entity_id: :entity_type}
    },
    %{
      name: "custom_fields",
      schema: Escalated.Schemas.CustomField,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:slug]]
    },
    %{
      name: "custom_object_records",
      schema: Escalated.Schemas.CustomObjectRecord,
      local_refs: %{custom_object_id: {"custom_objects", :id}},
      host_refs: [],
      unique_keys: [],
      polymorphic_refs: %{linked_entity_id: :linked_entity_type}
    },
    %{
      name: "custom_objects",
      schema: Escalated.Schemas.CustomObject,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:slug]]
    },
    %{
      name: "delayed_actions",
      schema: Escalated.Schemas.DelayedAction,
      local_refs: %{ticket_id: {"tickets", :id}, workflow_id: {"workflows", :id}},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "departments",
      schema: Escalated.Schemas.Department,
      local_refs: %{default_sla_policy_id: {"sla_policies", :id}},
      host_refs: [],
      unique_keys: [[:name], [:slug]]
    },
    %{
      name: "email_channels",
      schema: Escalated.Schemas.EmailChannel,
      local_refs: %{department_id: {"departments", :id}},
      host_refs: [],
      unique_keys: [[:email_address]]
    },
    %{
      name: "escalation_rules",
      schema: Escalated.Schemas.EscalationRule,
      local_refs: %{},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "holidays",
      schema: Escalated.Schemas.Holiday,
      local_refs: %{business_schedule_id: {"business_schedules", :id}},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "macros",
      schema: Escalated.Schemas.Macro,
      local_refs: %{},
      host_refs: [:created_by],
      unique_keys: []
    },
    %{
      name: "mentions",
      schema: Escalated.Schemas.Mention,
      local_refs: %{reply_id: {"replies", :id}},
      host_refs: [:user_id],
      unique_keys: [[:reply_id, :user_id]]
    },
    %{
      name: "newsletter_deliveries",
      schema: Escalated.Schemas.Newsletter.NewsletterDelivery,
      local_refs: %{contact_id: {"contacts", :id}, newsletter_id: {"newsletters", :id}},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "newsletter_list_members",
      schema: Escalated.Schemas.Newsletter.NewsletterListMember,
      local_refs: %{contact_id: {"contacts", :id}, list_id: {"newsletter_lists", :id}},
      host_refs: [:added_by],
      unique_keys: [[:list_id, :contact_id]]
    },
    %{
      name: "newsletter_lists",
      schema: Escalated.Schemas.Newsletter.NewsletterList,
      local_refs: %{},
      host_refs: [:created_by],
      unique_keys: []
    },
    %{
      name: "newsletter_templates",
      schema: Escalated.Schemas.Newsletter.NewsletterTemplate,
      local_refs: %{},
      host_refs: [:created_by],
      unique_keys: []
    },
    %{
      name: "newsletters",
      schema: Escalated.Schemas.Newsletter.Newsletter,
      local_refs: %{
        target_list_id: {"newsletter_lists", :id},
        template_id: {"newsletter_templates", :id}
      },
      host_refs: [:created_by, :sent_by],
      unique_keys: []
    },
    %{
      name: "permissions",
      schema: Escalated.Schemas.Permission,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:slug]]
    },
    %{
      name: "plugin_store",
      schema: Escalated.Schemas.PluginStoreRecord,
      local_refs: %{},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "plugins",
      schema: Escalated.Schemas.Plugin,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:slug]]
    },
    %{
      name: "replies",
      schema: Escalated.Schemas.Reply,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [:author_id],
      unique_keys: []
    },
    %{
      name: "role_permissions",
      schema: Escalated.Schemas.RolePermission,
      local_refs: %{permission_id: {"permissions", :id}, role_id: {"roles", :id}},
      host_refs: [],
      unique_keys: [[:role_id, :permission_id]]
    },
    %{
      name: "roles",
      schema: Escalated.Schemas.Role,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:slug]]
    },
    %{
      name: "satisfaction_ratings",
      schema: Escalated.Schemas.SatisfactionRating,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [],
      unique_keys: [[:ticket_id]],
      polymorphic_refs: %{rated_by_id: :rated_by_type}
    },
    %{
      name: "saved_views",
      schema: Escalated.Schemas.SavedView,
      local_refs: %{},
      host_refs: [:user_id],
      unique_keys: [[:user_id, :name]]
    },
    %{
      name: "settings",
      schema: Escalated.Schemas.EscalatedSetting,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:key]]
    },
    %{
      name: "side_conversation_replies",
      schema: Escalated.Schemas.SideConversationReply,
      local_refs: %{side_conversation_id: {"side_conversations", :id}},
      host_refs: [:author_id],
      unique_keys: []
    },
    %{
      name: "side_conversations",
      schema: Escalated.Schemas.SideConversation,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [:created_by],
      unique_keys: []
    },
    %{
      name: "skill_routing_departments",
      schema: Escalated.Schemas.SkillRoutingDepartment,
      local_refs: %{department_id: {"departments", :id}, skill_id: {"skills", :id}},
      host_refs: [],
      unique_keys: [[:skill_id, :department_id]]
    },
    %{
      name: "skill_routing_tags",
      schema: Escalated.Schemas.SkillRoutingTag,
      local_refs: %{skill_id: {"skills", :id}, tag_id: {"tags", :id}},
      host_refs: [],
      unique_keys: [[:skill_id, :tag_id]]
    },
    %{
      name: "skills",
      schema: Escalated.Schemas.Skill,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:slug], [:name]]
    },
    %{
      name: "sla_policies",
      schema: Escalated.Schemas.SlaPolicy,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:name]]
    },
    %{
      name: "tags",
      schema: Escalated.Schemas.Tag,
      local_refs: %{},
      host_refs: [],
      unique_keys: [[:name]]
    },
    %{
      name: "ticket_activities",
      schema: Escalated.Schemas.TicketActivity,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [:causer_id],
      unique_keys: []
    },
    %{
      name: "ticket_followers",
      schema: Escalated.Schemas.TicketFollower,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [:user_id],
      unique_keys: [[:ticket_id, :user_id]]
    },
    %{
      name: "ticket_links",
      schema: Escalated.Schemas.TicketLink,
      local_refs: %{child_ticket_id: {"tickets", :id}, parent_ticket_id: {"tickets", :id}},
      host_refs: [],
      unique_keys: [[:parent_ticket_id, :child_ticket_id, :link_type]]
    },
    %{
      name: "ticket_subjects",
      schema: Escalated.Schemas.TicketSubject,
      local_refs: %{ticket_id: {"tickets", :id}},
      host_refs: [],
      unique_keys: [[:ticket_id, :subject_type, :subject_id]],
      polymorphic_refs: %{subject_id: :subject_type}
    },
    %{
      name: "ticket_tags",
      schema: Escalated.Schemas.TicketTag,
      local_refs: %{tag_id: {"tags", :id}, ticket_id: {"tickets", :id}},
      host_refs: [],
      unique_keys: [[:ticket_id, :tag_id]]
    },
    %{
      name: "tickets",
      schema: Escalated.Schemas.Ticket,
      local_refs: %{
        contact_id: {"contacts", :id},
        department_id: {"departments", :id},
        sla_policy_id: {"sla_policies", :id}
      },
      host_refs: [:assigned_to, :snoozed_by],
      unique_keys: [],
      polymorphic_refs: %{requester_id: :requester_type}
    },
    %{
      name: "two_factors",
      schema: Escalated.Schemas.TwoFactor,
      local_refs: %{},
      host_refs: [:user_id],
      unique_keys: []
    },
    %{
      name: "webhook_deliveries",
      schema: Escalated.Schemas.WebhookDelivery,
      local_refs: %{webhook_id: {"webhooks", :id}},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "webhooks",
      schema: Escalated.Schemas.Webhook,
      local_refs: %{},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "workflow_logs",
      schema: Escalated.Schemas.WorkflowLog,
      local_refs: %{ticket_id: {"tickets", :id}, workflow_id: {"workflows", :id}},
      host_refs: [],
      unique_keys: []
    },
    %{
      name: "workflows",
      schema: Escalated.Schemas.Workflow,
      local_refs: %{},
      host_refs: [],
      unique_keys: []
    }
  ]

  @doc "Every merchant-owned table, including the two explicit join schemas."
  def entries, do: @entries
end
