defmodule Escalated.Tenancy.PublicUrlTest do
  use Escalated.DataCase, async: false

  import Escalated.NewsletterCase, only: [insert_contact!: 2, insert_newsletter!: 2]

  alias Escalated.Schemas.Newsletter.NewsletterDelivery
  alias Escalated.Services.Newsletter.{Dispatcher, RateLimit, Renderer}
  alias Escalated.Tenancy
  alias Escalated.Tenancy.PublicUrl

  defmodule Resolver do
    def public_url(tenant),
      do:
        Process.get(
          :public_url_override,
          "https://#{tenant}.example/merchants/#{tenant}/support/"
        )
  end

  defmodule WithoutPublicUrl do
  end

  setup do
    keys = [
      :tenancy_enabled,
      :tenant_resolver,
      :app_url,
      :enable_newsletters,
      :newsletter_mailer,
      :newsletter_tracking_enabled,
      :newsletter_rate_limit_per_minute,
      :newsletter_batch_size
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, Resolver)
    Application.put_env(:escalated, :app_url, "https://platform.example")
    Application.put_env(:escalated, :newsletter_tracking_enabled, true)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "rendered tracking and recipient links preserve each merchant mount path" do
    delivery = %{tracking_token: "delivery-token"}
    newsletter = %{subject: "Updates", body_markdown: "Hello", theme: "default"}
    contact = %{name: "Recipient", email: "recipient@example.test"}

    for tenant <- ["merchant-a", "merchant-b"] do
      Tenancy.run(tenant, fn ->
        base = "https://#{tenant}.example/merchants/#{tenant}/support"
        assert PublicUrl.base() == base
        assert Renderer.unsubscribe_url(delivery) == "#{base}/escalated/n/u/delivery-token"
        assert Renderer.view_in_browser_url(delivery) == "#{base}/escalated/n/v/delivery-token"
        html = Renderer.render(delivery, newsletter, contact)
        assert html =~ "#{base}/escalated/n/o/delivery-token.gif"
        refute html =~ "platform.example"
      end)
    end
  end

  test "dispatch uses the merchant URL for headers and rendered content" do
    Application.put_env(:escalated, :enable_newsletters, true)
    Application.put_env(:escalated, :newsletter_rate_limit_per_minute, 60)
    Application.put_env(:escalated, :newsletter_batch_size, 50)
    recipient = self()

    Application.put_env(:escalated, :newsletter_mailer, fn message ->
      send(recipient, {:mail, message})
    end)

    for tenant <- ["merchant-a", "merchant-b"] do
      Tenancy.run(tenant, fn ->
        RateLimit.reset()
        delivery = pending_delivery!()
        Dispatcher.dispatch_batch()
        assert_receive {:mail, message}
        base = PublicUrl.base()

        assert message.headers["List-Unsubscribe"] ==
                 "<#{base}/escalated/n/u/#{delivery.tracking_token}>"

        assert message.headers["Message-ID"] =~ "@#{tenant}.example>"
        assert message.html =~ "#{base}/escalated/n/v/#{delivery.tracking_token}"
        assert Escalated.repo().get!(NewsletterDelivery, delivery.id).status == "sent"
        RateLimit.reset()
      end)
    end
  end

  test "tenant delivery fails closed when the public URL callback is missing" do
    Application.put_env(:escalated, :tenant_resolver, WithoutPublicUrl)

    Tenancy.run("merchant-a", fn ->
      assert_raise Tenancy.Error, fn -> PublicUrl.base() end
      assert_raise Tenancy.Error, fn -> Renderer.unsubscribe_url(%{tracking_token: "token"}) end
    end)

    assert_raise Tenancy.Error, fn -> PublicUrl.base() end
  end

  test "tenant URLs reject unsafe schemes, ambiguous authorities and request suffixes" do
    urls = [
      nil,
      "http://merchant.example",
      "//merchant.example",
      "https:///support",
      "https://user@merchant.example",
      "https://merchant.example/support?tenant=a",
      "https://merchant.example/support#fragment",
      "https://merchant.example:0",
      "https://merchant.example:65536",
      "https://merchant.example/with space",
      "https://merchant.example/\\other",
      "https://merchant.example/\r\ninjected"
    ]

    Tenancy.run("merchant-a", fn ->
      for url <- urls do
        Process.put(:public_url_override, url)
        assert_raise Tenancy.Error, fn -> PublicUrl.base() end
      end
    end)
  end

  test "single-tenant links preserve the configured app URL and localhost fallback" do
    Application.put_env(:escalated, :tenancy_enabled, false)
    Application.put_env(:escalated, :tenant_resolver, WithoutPublicUrl)
    Application.put_env(:escalated, :app_url, "http://localhost:4000/support/")
    assert PublicUrl.base() == "http://localhost:4000/support"
    Application.delete_env(:escalated, :app_url)
    assert PublicUrl.base() == "http://localhost"
  end

  defp pending_delivery! do
    repo = Escalated.repo()
    newsletter = insert_newsletter!(repo, %{status: "sending", body_markdown: "Hello"})
    contact = insert_contact!(repo, %{email: "recipient@example.test"})

    repo.insert!(
      NewsletterDelivery.changeset(%NewsletterDelivery{}, %{
        newsletter_id: newsletter.id,
        contact_id: contact.id,
        email_at_send: contact.email,
        tracking_token: "delivery-#{Tenancy.current_id!()}",
        created_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
  end
end
