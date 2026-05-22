defmodule Escalated.Services.Newsletter.Renderer do
  @moduledoc """
  Renders a newsletter delivery to themed HTML.

  Stage 1: Markdown -> canonical HTML (host integrators register a
           renderer via `Application.put_env(:escalated, :newsletter_markdown_renderer, fun)`;
           defaults to a minimal escape+paragraph fallback).
  Stage 2: Theme wrapping via EEx (`<slug>.html.eex`).
  Stage 3: Optional click rewriting + tracking pixel injection.
  """

  @allowed_schemes ~w(http https mailto tel)

  def render(delivery, newsletter, contact, template \\ nil) do
    body_md = newsletter.body_markdown || (template && template.body_markdown) || ""
    theme_slug = newsletter.theme || (template && template.theme) || default_theme()

    body =
      body_md
      |> markdown_to_html()
      |> resolve_merge_fields(contact, delivery)

    themed = render_theme(theme_slug, %{
      subject: newsletter.subject,
      body: body,
      unsubscribe_url: unsubscribe_url(delivery),
      view_in_browser_url: view_in_browser_url(delivery),
      brand: brand()
    })

    if tracking_enabled?() do
      themed
      |> rewrite_links(delivery)
      |> inject_pixel(delivery)
    else
      themed
    end
  end

  def unsubscribe_url(delivery), do: "#{base_url()}/escalated/n/u/#{delivery.tracking_token}"
  def view_in_browser_url(delivery), do: "#{base_url()}/escalated/n/v/#{delivery.tracking_token}"

  # ----

  defp base_url, do: String.trim_trailing(Application.get_env(:escalated, :app_url, "http://localhost"), "/")
  defp default_theme, do: Application.get_env(:escalated, :newsletter_default_theme, "default")
  defp tracking_enabled?, do: Application.get_env(:escalated, :newsletter_tracking_enabled, true)

  defp brand do
    %{
      name: Application.get_env(:escalated, :app_name, "Support"),
      accent: Application.get_env(:escalated, :newsletter_brand_accent, "#2563eb"),
      logo_url: Application.get_env(:escalated, :newsletter_brand_logo_url),
      physical_address: Application.get_env(:escalated, :newsletter_brand_physical_address)
    }
  end

  defp markdown_to_html(md) do
    case Application.get_env(:escalated, :newsletter_markdown_renderer) do
      fun when is_function(fun, 1) -> fun.(md)
      _ ->
        escaped = md |> to_string() |> Plug.HTML.html_escape()
        "<p>" <> String.replace(escaped, ~r/\n{2,}/, "</p><p>") <> "</p>"
    end
  end

  defp resolve_merge_fields(html, contact, delivery) do
    Regex.replace(~r/\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/, html, fn _, path ->
      Plug.HTML.html_escape(resolve_path(String.trim(path), contact, delivery))
    end)
  end

  defp resolve_path("contact.name", contact, _d), do: to_string(Map.get(contact, :name) || "")
  defp resolve_path("contact.first_name", contact, _d) do
    case (Map.get(contact, :name) || "") |> to_string() |> String.split(" ", parts: 2) do
      [first | _] -> first
      _ -> ""
    end
  end
  defp resolve_path("contact.email", contact, _d), do: to_string(Map.get(contact, :email) || "")
  defp resolve_path("unsubscribe_url", _c, d), do: unsubscribe_url(d)
  defp resolve_path("view_in_browser_url", _c, d), do: view_in_browser_url(d)
  defp resolve_path("contact.metadata." <> key, contact, _d) do
    meta = Map.get(contact, :metadata) || %{}
    case Map.get(meta, key) do
      nil -> ""
      v -> to_string(v)
    end
  end
  defp resolve_path(_, _, _), do: ""

  defp render_theme(slug, assigns) do
    themes_dir = themes_dir()
    path = Path.join(themes_dir, "#{slug}.html.eex")
    path = if File.exists?(path), do: path, else: Path.join(themes_dir, "default.html.eex")
    EEx.eval_file(path, assigns: assigns)
  end

  defp themes_dir do
    Application.get_env(:escalated, :newsletter_themes_dir) ||
      Application.app_dir(:escalated, "priv/templates/newsletter_themes")
  end

  defp rewrite_links(html, delivery) do
    unsub = unsubscribe_url(delivery)
    view = view_in_browser_url(delivery)

    Regex.replace(~r/(<a\s[^>]*\bhref=)("|')(.*?)\2/i, html, fn full, prefix, quote, href ->
      cond do
        href == "" or String.starts_with?(href, "#") ->
          full

        true ->
          scheme = href |> String.split(":", parts: 2) |> hd() |> String.downcase()
          cond do
            scheme not in @allowed_schemes -> "#{prefix}#{quote}##{quote}"
            scheme in ["mailto", "tel"] -> full
            String.starts_with?(href, unsub) or String.starts_with?(href, view) -> full
            true ->
              encoded = Base.url_encode64(href, padding: false)
              tracked = "#{base_url()}/escalated/n/c/#{delivery.tracking_token}?u=#{encoded}"
              "#{prefix}#{quote}#{tracked}#{quote}"
          end
      end
    end)
  end

  defp inject_pixel(html, delivery) do
    url = "#{base_url()}/escalated/n/o/#{delivery.tracking_token}.gif"
    pixel = "<img src=\"#{Plug.HTML.html_escape(url)}\" width=\"1\" height=\"1\" alt=\"\" />"
    if String.contains?(html, "</body>") do
      String.replace(html, "</body>", "#{pixel}</body>")
    else
      html <> pixel
    end
  end
end
