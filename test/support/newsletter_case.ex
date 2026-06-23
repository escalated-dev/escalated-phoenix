defmodule Escalated.NewsletterCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Escalated.NewsletterCase
      import Ecto.Query
      alias Escalated.Schemas.Contact
      alias Escalated.Schemas.Newsletter.Newsletter
      alias Escalated.Schemas.Newsletter.NewsletterDelivery
      alias Escalated.Schemas.Newsletter.NewsletterList
      alias Escalated.Schemas.Newsletter.NewsletterListMember
    end
  end

  setup tags do
    Escalated.DataCase.setup_sandbox(tags)
    on_exit(fn -> restore_newsletter_env() end)
    enable_newsletters!()
    {:ok, repo: Escalated.repo()}
  end

  def enable_newsletters! do
    Application.put_env(:escalated, :enable_newsletters, true)
    Application.put_env(:escalated, :newsletter_rate_limit_per_minute, 60)
    Application.put_env(:escalated, :newsletter_batch_size, 50)
    Application.put_env(:escalated, :app_url, "http://localhost")
    Application.put_env(:escalated, :newsletter_markdown_renderer, fn md -> "<p>#{md}</p>" end)

    Escalated.Services.Newsletter.RateLimit.reset()
  end

  def restore_newsletter_env do
    Application.delete_env(:escalated, :enable_newsletters)
    Application.delete_env(:escalated, :newsletter_mailer)
    Application.delete_env(:escalated, :newsletter_rate_limit_per_minute)
    Application.delete_env(:escalated, :newsletter_batch_size)
    Application.delete_env(:escalated, :newsletter_tracking_enabled)
    Application.delete_env(:escalated, :newsletter_markdown_renderer)
  end

  def insert_contact!(repo, attrs \\ %{}) do
    defaults = %{email: "user#{System.unique_integer()}@example.com", name: "User"}

    {:ok, c} =
      repo.insert(
        Escalated.Schemas.Contact.changeset(
          %Escalated.Schemas.Contact{},
          Map.merge(defaults, attrs)
        )
      )

    c
  end

  def insert_list!(repo, attrs \\ %{}) do
    defaults = %{name: "List", kind: "static", filter_json: %{"rules" => []}}

    {:ok, l} =
      repo.insert(
        Escalated.Schemas.Newsletter.NewsletterList.changeset(
          %Escalated.Schemas.Newsletter.NewsletterList{},
          Map.merge(defaults, attrs)
        )
      )

    l
  end

  def insert_newsletter!(repo, attrs \\ %{}) do
    list = insert_list!(repo)

    defaults = %{
      subject: "Hi",
      from_email: "sender@example.com",
      target_list_id: list.id,
      status: "draft"
    }

    {:ok, n} =
      repo.insert(
        Escalated.Schemas.Newsletter.Newsletter.changeset(
          %Escalated.Schemas.Newsletter.Newsletter{},
          Map.merge(defaults, attrs)
        )
      )

    n
  end
end
