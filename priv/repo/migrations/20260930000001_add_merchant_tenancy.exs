defmodule Escalated.Repo.Migrations.AddMerchantTenancy do
  use Ecto.Migration
  require Ecto.Query

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  # The empty tenant is exclusively the legacy, single-tenant namespace.
  # Enabling merchant tenancy never adopts these rows implicitly.
  @tables ~w(
    agent_capacity agent_profiles agent_skills article_categories
    articles attachments audit_logs automations
    business_schedules canned_responses chat_routing_rules chat_sessions
    contacts custom_field_values custom_fields custom_object_records
    custom_objects delayed_actions departments email_channels
    escalation_rules holidays macros mentions
    newsletter_deliveries newsletter_list_members newsletter_lists newsletter_templates
    newsletters permissions plugin_store plugins
    replies role_permissions roles satisfaction_ratings
    saved_views settings side_conversation_replies side_conversations
    skill_routing_departments skill_routing_tags skills sla_policies
    tags ticket_activities ticket_followers ticket_links
    ticket_subjects ticket_tags tickets two_factors
    webhook_deliveries webhooks workflow_logs workflows
  )
  @pivots ~w(ticket_tags role_permissions)

  # Retain the existing names so existing Ecto unique_constraint declarations
  # continue turning collisions into changeset errors after widening each key.
  @unique_indexes [
    {"sla_policies", [:name], "#{@prefix}sla_policies_name_index"},
    {"departments", [:name], "#{@prefix}departments_name_index"},
    {"departments", [:slug], "#{@prefix}departments_slug_index"},
    {"tags", [:name], "#{@prefix}tags_name_index"},
    {"ticket_tags", [:ticket_id, :tag_id], "#{@prefix}ticket_tags_ticket_id_tag_id_index"},
    {"agent_profiles", [:user_id], "#{@prefix}agent_profiles_user_id_index"},
    {"saved_views", [:user_id, :name], "#{@prefix}saved_views_user_id_name_index"},
    {"email_channels", [:email_address], "#{@prefix}email_channels_email_address_index"},
    {"custom_fields", [:slug], "#{@prefix}custom_fields_slug_index"},
    {"custom_field_values", [:custom_field_id, :entity_type, :entity_id], "unique_field_entity"},
    {"custom_objects", [:slug], "#{@prefix}custom_objects_slug_index"},
    {"settings", [:key], "#{@prefix}settings_key_index"},
    {"contacts", [:email], "#{@prefix}contacts_email_index"},
    {"skills", [:slug], "#{@prefix}skills_slug_index"},
    {"skills", [:name], "#{@prefix}skills_name_index"},
    {"skill_routing_tags", [:skill_id, :tag_id],
     "#{@prefix}skill_routing_tags_skill_id_tag_id_index"},
    {"skill_routing_departments", [:skill_id, :department_id],
     "#{@prefix}skill_routing_departments_skill_id_department_id_index"},
    {"agent_skills", [:user_id, :skill_id], "#{@prefix}agent_skills_user_id_skill_id_index"},
    {"newsletter_list_members", [:list_id, :contact_id],
     "#{@prefix}newsletter_list_members_list_id_contact_id_index"},
    {"ticket_subjects", [:ticket_id, :subject_type, :subject_id],
     "escalated_ticket_subject_unique"},
    {"permissions", [:slug], "#{@prefix}permissions_slug_index"},
    {"roles", [:slug], "#{@prefix}roles_slug_index"},
    {"role_permissions", [:role_id, :permission_id],
     "#{@prefix}role_permissions_role_id_permission_id_index"},
    {"satisfaction_ratings", [:ticket_id], "#{@prefix}satisfaction_ratings_ticket_id_index"},
    {"agent_capacity", [:user_id, :channel], "#{@prefix}agent_capacity_user_id_channel_index"},
    {"ticket_links", [:parent_ticket_id, :child_ticket_id, :link_type],
     "#{@prefix}ticket_links_unique"},
    {"article_categories", [:slug], "#{@prefix}article_categories_slug_index"},
    {"articles", [:slug], "#{@prefix}articles_slug_index"},
    {"ticket_followers", [:ticket_id, :user_id],
     "#{@prefix}ticket_followers_ticket_id_user_id_index"},
    {"plugins", [:slug], "#{@prefix}plugins_slug_index"},
    {"mentions", [:reply_id, :user_id], "#{@prefix}mentions_reply_id_user_id_index"}
  ]

  # MySQL may use a former unique index to enforce a foreign key. Give that
  # foreign key an explicit index before replacing the unique index with one
  # whose leading column is tenant_id. Keep it until rollback restores the key.
  @reference_indexes [
    {"custom_field_values", :custom_field_id},
    {"mentions", :reply_id},
    {"newsletter_list_members", :list_id},
    {"role_permissions", :role_id},
    {"satisfaction_ratings", :ticket_id},
    {"skill_routing_departments", :skill_id},
    {"skill_routing_tags", :skill_id},
    {"ticket_followers", :ticket_id},
    {"ticket_links", :parent_ticket_id},
    {"ticket_subjects", :ticket_id},
    {"ticket_tags", :ticket_id}
  ]

  def up do
    for name <- @tables do
      alter table(source(name)) do
        add :tenant_id, :string, tenant_options()
      end

      if name in @pivots do
        create index(source(name), [:tenant_id], name: index_name(name, "rows"))
      else
        create unique_index(source(name), [:tenant_id, :id], name: index_name(name, "rows"))
      end
    end

    for {name, field} <- @reference_indexes do
      create index(source(name), [field], name: index_name(name, Atom.to_string(field)))
    end

    for {name, fields, existing_name} <- @unique_indexes do
      drop_existing_unique(name, fields, existing_name)
      create unique_index(source(name), [:tenant_id | fields], name: existing_name)
    end
  end

  def down do
    # Check all tables before scheduling any destructive DDL. A downgrade must
    # never silently erase tenant identity or merge merchant data into legacy.
    for name <- @tables do
      table_name = source(name)

      assigned =
        Ecto.Query.from(row in table_name,
          where: field(row, :tenant_id) != "",
          select: 1,
          limit: 1
        )

      if repo().exists?(assigned) do
        raise "Cannot roll back merchant tenancy while #{table_name} contains assigned tenant rows"
      end
    end

    for {name, fields, existing_name} <- @unique_indexes do
      drop index(source(name), [:tenant_id | fields], name: existing_name)
      create unique_index(source(name), fields, name: existing_name)
    end

    for {name, field} <- @reference_indexes do
      drop index(source(name), [field], name: index_name(name, Atom.to_string(field)))
    end

    for name <- @tables do
      fields = if name in @pivots, do: [:tenant_id], else: [:tenant_id, :id]
      drop index(source(name), fields, name: index_name(name, "rows"))

      alter table(source(name)) do
        remove :tenant_id
      end
    end
  end

  defp tenant_options do
    options = [size: 128, default: "", null: false]

    if repo().__adapter__() == Ecto.Adapters.MyXQL,
      do: Keyword.put(options, :collation, "utf8mb4_bin"),
      else: options
  end

  defp source(name), do: @prefix <> name

  # Older installations used an automatically named ticket-link index. The
  # schema already recognizes both spellings; migrate those installations too.
  defp drop_existing_unique("ticket_links" = name, fields, existing_name) do
    derived = source(name) <> "_" <> Enum.map_join(fields, "_", &Atom.to_string/1) <> "_index"

    [existing_name, derived, binary_part(derived, 0, min(byte_size(derived), 63))]
    |> Enum.uniq()
    |> Enum.each(&drop_optional_index(name, fields, &1))
  end

  defp drop_existing_unique(name, fields, existing_name) do
    drop index(source(name), fields, name: existing_name)
  end

  defp drop_optional_index(name, fields, index_name) do
    if repo().__adapter__() == Ecto.Adapters.MyXQL do
      # MyXQL cannot emit DROP INDEX IF EXISTS. Check the exact migration-owned
      # table/index instead; values remain bound SQL parameters.
      if byte_size(index_name) <= 64 and mysql_index_exists?(source(name), index_name),
        do: drop(index(source(name), fields, name: index_name))
    else
      drop_if_exists index(source(name), fields, name: index_name)
    end
  end

  defp mysql_index_exists?(table_name, index_name) do
    result =
      Ecto.Adapters.SQL.query!(
        repo(),
        """
        SELECT 1 FROM information_schema.statistics
        WHERE table_schema = DATABASE() AND table_name = ? AND index_name = ? LIMIT 1
        """,
        [table_name, index_name]
      )

    result.num_rows > 0
  end

  # Bounded names also work with a custom prefix and PostgreSQL's 63-byte cap.
  defp index_name(name, purpose) do
    hash = :crypto.hash(:sha256, source(name) <> ":" <> purpose)
    "escalated_tenant_" <> binary_part(Base.encode16(hash, case: :lower), 0, 24)
  end
end
