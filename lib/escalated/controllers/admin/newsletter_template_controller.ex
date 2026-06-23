defmodule Escalated.Controllers.Admin.NewsletterTemplateController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]
  import Ecto.Query

  alias Escalated.Controllers.NewsletterHttp, as: NH
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.Newsletter.NewsletterTemplate
  alias Escalated.Services.Newsletter.Permission

  def index(conn, _params) do
    conn = Permission.require_manage!(conn)

    templates =
      Escalated.repo().all(from(t in NewsletterTemplate, order_by: [desc: t.inserted_at]))

    UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Templates/Index", %{
      templates: templates
    })
  end

  def create(conn, _params) do
    conn = Permission.require_manage!(conn)

    UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Templates/Create", %{
      themes: NH.discover_themes()
    })
  end

  def store(conn, params) do
    conn = Permission.require_manage!(conn)

    with {:ok, attrs} <- validate_form(params) do
      attrs = Map.put(attrs, :created_by, NH.user_id(conn))

      case Escalated.repo().insert(NewsletterTemplate.changeset(%NewsletterTemplate{}, attrs)) do
        {:ok, _} -> NH.redirect(conn, "#{NH.newsletters_base()}/templates")
        {:error, cs} -> NH.bad_request(conn, errors(cs))
      end
    else
      {:error, e} -> NH.bad_request(conn, e)
    end
  end

  def show(conn, %{"template" => id}) do
    conn = Permission.require_manage!(conn)

    with %NewsletterTemplate{} = template <- Escalated.repo().get(NewsletterTemplate, id) do
      UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Templates/Show", %{
        template: template,
        themes: NH.discover_themes(),
        isNew: false
      })
    else
      _ -> conn |> put_status(404) |> json(%{error: "Template not found"})
    end
  end

  def update(conn, %{"template" => id} = params) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %NewsletterTemplate{} = template <- repo.get(NewsletterTemplate, id),
         {:ok, attrs} <- validate_form(params) do
      case repo.update(NewsletterTemplate.changeset(template, attrs)) do
        {:ok, _} -> NH.redirect(conn, "#{NH.newsletters_base()}/templates/#{template.id}")
        {:error, cs} -> NH.bad_request(conn, errors(cs))
      end
    else
      nil -> conn |> put_status(404) |> json(%{error: "Template not found"})
      {:error, e} -> NH.bad_request(conn, e)
    end
  end

  def delete(conn, %{"template" => id}) do
    conn = Permission.require_manage!(conn)

    with %NewsletterTemplate{} = template <- Escalated.repo().get(NewsletterTemplate, id) do
      Escalated.repo().delete(template)
      NH.redirect(conn, "#{NH.newsletters_base()}/templates")
    else
      _ -> conn |> put_status(404) |> json(%{error: "Template not found"})
    end
  end

  defp validate_form(params) do
    checks = [
      {:name, NH.required_string(params, "name", 255)},
      {:theme, NH.required_string(params, "theme", 64)},
      {:subject_template, NH.optional_string(params, "subject_template", 998)},
      {:body_markdown, NH.required_string(params, "body_markdown")},
      {:merge_fields_schema, {:ok, merge_schema(params)}}
    ]

    case NH.collect_errors(Enum.map(checks, fn {_, r} -> r end)) do
      errors when map_size(errors) > 0 -> {:error, errors}
      _ -> {:ok, Enum.into(checks, %{}, fn {k, {:ok, v}} -> {k, v} end)}
    end
  end

  defp merge_schema(params) do
    case Map.get(params, "merge_fields_schema") || Map.get(params, :merge_fields_schema) do
      v when is_map(v) -> v
      _ -> nil
    end
  end

  defp errors(cs), do: Ecto.Changeset.traverse_errors(cs, fn {m, _} -> m end)
end
