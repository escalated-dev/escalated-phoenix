defmodule Escalated.Permissions.Catalog do
  @moduledoc """
  Canonical Escalated permission definitions for host RBAC seeding.
  """

  @newsletter_permissions [
    %{
      slug: "newsletters.manage",
      name: "Manage newsletters",
      group: "Newsletters",
      description: "Create, edit, delete drafts and lists/templates; send test emails."
    },
    %{
      slug: "newsletters.send",
      name: "Send newsletters",
      group: "Newsletters",
      description: "Schedule or send newsletters now."
    }
  ]

  def newsletter, do: @newsletter_permissions

  def all, do: newsletter()
end
