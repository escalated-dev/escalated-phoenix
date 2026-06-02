defmodule Escalated.Controllers.Admin.NewsletterController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Controllers.NewsletterHttp, as: NH
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.Contact
  alias Escalated.Schemas.Newsletter.{Newsletter, NewsletterDelivery, NewsletterList, NewsletterTemplate}
  alias Escalated.Services.Newsletter.{Permission, Planner, Renderer, Settings}

  def index(conn, params) do
    conn = Permission.require_manage!(conn)
    tab = params["tab"] || "drafts"
    statuses = tab_statuses(tab)
    repo = Escalated.repo()

    newsletters =
      from(n in Newsletter,
        where: n.status in ^statuses,
        order_by: [desc: n.inserted_at],
        limit: 50
      )
      |> repo.all()
      |> Enum.map(&serialize_newsletter(&1, repo))

    UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Index", %{
      newsletters: newsletters,
      tab: tab
    })
  end

  def create(conn, _params) do
    conn = Permission.require_manage!(conn)
    UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Compose", compose_props())
  end

  def store(conn, params) do
    conn = Permission.require_manage!(conn)

    with {:ok, data} <- validate_form(params) do
      conn = maybe_require_send!(conn, data.status)

      if sending_status?(data.status) and not NH.mail_configured?() do
        NH.bad_request(conn, %{from_email: ["Outbound mail is not configured."]})
      else
        attrs = Map.put(data, :created_by, NH.user_id(conn))

        case Escalated.repo().insert(Newsletter.changeset(%Newsletter{}, attrs)) do
          {:ok, newsletter} ->
            if data.status == "sending", do: Planner.plan(newsletter)
            NH.redirect(conn, "#{NH.newsletters_base()}/#{newsletter.id}")

          {:error, cs} ->
            NH.bad_request(conn, format_changeset(cs))
        end
      end
    else
      {:error, errors} -> NH.bad_request(conn, errors)
    end
  end

  def preview(conn, params) do
    conn = Permission.require_manage!(conn)

    newsletter = %Newsletter{
      subject: param(params, "subject"),
      from_email: param(params, "from_email") || "preview@example.test",
      body_markdown: param(params, "body_markdown"),
      theme: param(params, "theme") || "default",
      target_list_id: 0
    }

    contact = %{id: 0, email: "preview@example.test", name: "Preview User", metadata: %{}}
    delivery = %{tracking_token: "preview", newsletter_id: 0, contact_id: 0, email_at_send: contact.email}

    json(conn, %{html: Renderer.render(delivery, newsletter, contact)})
  end

  def test_send(conn, params) do
    conn = Permission.require_send!(conn)

    with {:ok, data} <- validate_form(params) do
      if not NH.mail_configured?() do
        NH.bad_request(conn, %{from_email: ["Outbound mail is not configured."]})
      else
        user = conn.assigns[:current_user] || %{}
        contact = %{id: NH.user_id(conn) || 0, email: Map.get(user, :email) || data.from_email, name: Map.get(user, :name) || "Tester", metadata: %{}}
        newsletter = struct(Newsletter, Map.merge(data, %{id: 0}))
        token = 20 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
        delivery = %{tracking_token: token, newsletter_id: 0, contact_id: contact.id, email_at_send: contact.email, is_test: true}
        html = Renderer.render(delivery, newsletter, contact)

        mailer = Application.fetch_env!(:escalated, :newsletter_mailer)

        mailer.(%{
          to: contact.email,
          from: format_from(data),
          subject: "[TEST] #{data.subject}",
          html: html
        })

        json(conn, %{ok: true})
      end
    else
      {:error, errors} -> NH.bad_request(conn, errors)
    end
  end

  def show(conn, %{"newsletter" => id} = params) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %Newsletter{} = newsletter <- repo.get(Newsletter, id) do
      tab = params["tab"] || "overview"
      status_filter = params["status"]

      deliveries_query =
        from(d in NewsletterDelivery,
          where: d.newsletter_id == ^newsletter.id and d.is_test == false,
          order_by: [desc: d.id],
          limit: 100
        )

      deliveries_query =
        if status_filter && status_filter != "" do
          where(deliveries_query, [d], d.status == ^status_filter)
        else
          deliveries_query
        end

      deliveries =
        deliveries_query
        |> repo.all()
        |> Enum.map(fn d ->
          contact = repo.get(Contact, d.contact_id)
          %{id: d.id, status: d.status, email_at_send: d.email_at_send, contact: %{id: contact && contact.id, name: contact && contact.name, email: contact && contact.email}}
        end)

      UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Show", %{
        newsletter: serialize_newsletter(newsletter, repo),
        deliveries: deliveries,
        topClicks: [],
        tab: tab
      })
    else
      _ -> conn |> put_status(404) |> json(%{error: "Newsletter not found"})
    end
  end

  def edit(conn, %{"newsletter" => id}) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %Newsletter{} = newsletter <- repo.get(Newsletter, id) do
      if newsletter.status not in ["draft", "scheduled"] do
        NH.abort422(conn, "Only drafts and scheduled newsletters can be edited")
      else
        UIRenderer.render_page(conn, "Escalated/Admin/Newsletters/Edit", Map.merge(compose_props(), %{newsletter: newsletter}))
      end
    else
      _ -> conn |> put_status(404) |> json(%{error: "Newsletter not found"})
    end
  end

  def update(conn, %{"newsletter" => id} = params) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %Newsletter{} = newsletter <- repo.get(Newsletter, id),
         {:ok, data} <- validate_form(params) do
      conn = maybe_require_send!(conn, data.status)

      case repo.update(Newsletter.changeset(newsletter, data)) do
        {:ok, updated} ->
          if data.status == "sending", do: Planner.plan(updated)
          NH.redirect(conn, "#{NH.newsletters_base()}/#{updated.id}")

        {:error, cs} ->
          NH.bad_request(conn, format_changeset(cs))
      end
    else
      nil -> conn |> put_status(404) |> json(%{error: "Newsletter not found"})
      {:error, errors} -> NH.bad_request(conn, errors)
    end
  end

  def delete(conn, %{"newsletter" => id}) do
    conn = Permission.require_manage!(conn)
    repo = Escalated.repo()

    with %Newsletter{} = newsletter <- repo.get(Newsletter, id) do
      if newsletter.status != "draft" do
        NH.abort422(conn, "Only drafts can be deleted")
      else
        repo.delete(newsletter)
        NH.redirect(conn, NH.newsletters_base())
      end
    else
      _ -> conn |> put_status(404) |> json(%{error: "Newsletter not found"})
    end
  end

  defp validate_form(params) do
    checks = [
      {:subject, NH.required_string(params, "subject", 998)},
      {:from_email, NH.assert_email(param(params, "from_email"), "from_email", true)},
      {:from_name, NH.optional_string(params, "from_name", 255)},
      {:reply_to, NH.assert_email(param(params, "reply_to"), "reply_to")},
      {:target_list_id, NH.required_integer(params, "target_list_id")},
      {:template_id, NH.optional_integer(params, "template_id")},
      {:theme, NH.optional_string(params, "theme", 64)},
      {:body_markdown, NH.optional_string(params, "body_markdown")},
      {:status, NH.assert_one_of(param(params, "status") || "draft", "status", ~w(draft scheduled sending))},
      {:scheduled_at, NH.optional_date_after_now(params, "scheduled_at")}
    ]

    errors = NH.collect_errors(Enum.map(checks, fn {_k, r} -> r end))

    if map_size(errors) > 0 do
      {:error, errors}
    else
      attrs =
        Enum.into(checks, %{}, fn {key, {:ok, val}} -> {key, val} end)

      repo = Escalated.repo()

      cond do
        is_nil(repo.get(NewsletterList, attrs.target_list_id)) ->
          {:error, %{"target_list_id" => ["does not exist"]}}

        attrs.template_id && is_nil(repo.get(NewsletterTemplate, attrs.template_id)) ->
          {:error, %{"template_id" => ["does not exist"]}}

        true ->
          {:ok, attrs}
      end
    end
  end

  defp compose_props do
    repo = Escalated.repo()

    %{
      lists: NH.lists_with_counts(repo),
      templates: repo.all(from(t in NewsletterTemplate, select: %{id: t.id, name: t.name})),
      themes: NH.discover_themes(),
      mailConfigured: NH.mail_configured?(),
      canSend: true,
      defaultFromEmail: Settings.read("default_from"),
      defaultReplyTo: Settings.read("default_reply_to"),
      defaultTheme: Settings.read("default_theme") || "default"
    }
  end

  defp serialize_newsletter(newsletter, repo) do
    list = if newsletter.target_list_id, do: repo.get(NewsletterList, newsletter.target_list_id)

    Map.take(newsletter, [
      :id,
      :subject,
      :from_email,
      :from_name,
      :reply_to,
      :target_list_id,
      :template_id,
      :theme,
      :body_markdown,
      :status,
      :scheduled_at,
      :sent_at,
      :summary_total,
      :summary_sent,
      :summary_opened,
      :summary_clicked,
      :summary_bounced,
      :summary_complained
    ])
    |> Map.put(:targetList, list && %{id: list.id, name: list.name, kind: list.kind})
  end

  defp tab_statuses("scheduled"), do: ~w(scheduled sending paused)
  defp tab_statuses("sent"), do: ~w(sent failed)
  defp tab_statuses(_), do: ~w(draft)

  defp sending_status?(status), do: status in ["scheduled", "sending"]

  defp maybe_require_send!(conn, status) do
    if sending_status?(status), do: Permission.require_send!(conn), else: conn
  end

  defp format_from(%{from_name: name, from_email: email}) when is_binary(name) and name != "",
    do: "\"#{name}\" <#{email}>"

  defp format_from(%{from_email: email}), do: email

  defp param(params, key), do: Map.get(params, key) || Map.get(params, to_string(key))

  defp format_changeset(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end)
  end
end
