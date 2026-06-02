defmodule Escalated.Services.Newsletter.RendererTest do
  use Escalated.NewsletterCase, async: false

  alias Escalated.Services.Newsletter.Renderer

  setup do
    Application.put_env(:escalated, :newsletter_markdown_renderer, fn _md ->
      "<p>Hello Maria</p><p><a href=\"https://example.com\">Go</a></p>"
    end)

    :ok
  end

  test "renders merge fields and tracking links" do
    delivery = %{tracking_token: "tok-abc"}
    newsletter = %{subject: "Hi", body_markdown: "# Hello {{ contact.first_name }}", theme: "default", from_email: "a@b.com"}
    contact = %{name: "Maria Lopez", email: "maria@example.com", metadata: %{}}

    newsletter =
      Map.put(
        newsletter,
        :body_markdown,
        "# Hello {{ contact.first_name }}\n\n[Go](https://example.com)"
      )
    html = Renderer.render(delivery, newsletter, contact)

    assert html =~ "Maria"
    assert html =~ "/escalated/n/c/tok-abc?u="
    refute html =~ "https://example.com"
    assert html =~ "/escalated/n/o/tok-abc"
  end

  test "tracking disabled preserves links", %{repo: _} do
    Application.put_env(:escalated, :newsletter_tracking_enabled, false)
    body = ~s(<a href="https://example.com">Go</a>)
    delivery = %{tracking_token: "tok"}
    newsletter = %{subject: "S", body_markdown: body, theme: "default"}
    contact = %{name: "A", email: "a@example.com", metadata: %{}}
    html = Renderer.render(delivery, newsletter, contact)
    assert html =~ "https://example.com"
    refute html =~ "/escalated/n/o/"
  end
end
