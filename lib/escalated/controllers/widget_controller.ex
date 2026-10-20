defmodule Escalated.Controllers.WidgetController do
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  import Ecto.Query
  alias Escalated.Controllers.Api.GuestTicketController
  alias Escalated.Controllers.GuestAccessController, as: AccessController
  alias Escalated.Controllers.GuestTicketView
  alias Escalated.Schemas.{Article, ArticleCategory}
  alias Escalated.Services.{GeneralSettings, GuestAccess, TicketService}
  alias Escalated.{WidgetDepartments, WidgetMetadata}

  @excerpt_length 150

  def config(conn, _params) do
    if Escalated.Plugs.EnsureWidgetEnabled.enabled?(),
      do: enabled_config(conn),
      else: disabled_config(conn)
  end

  # Matches Laravel: a disabled widget answers 403 `{"enabled": false}`, so the
  # embed (and anything keyed on the status) can tell it is off.
  defp disabled_config(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(403)
    |> json(%{enabled: false})
  end

  defp enabled_config(conn) do
    base = widget_settings()

    settings =
      base
      # The shared widget reads `color`; `primary_color` stays for older clients.
      |> Map.put_new(:color, base.primary_color)
      |> Map.put_new(:position, "bottom-right")
      |> Map.put(:departments, WidgetDepartments.list())
      |> Map.put(:kb_enabled, knowledge_base(conn) == :ok)
      |> Map.put(:guest_tickets_enabled, base.enabled not in [false, nil])
      # Status lookup proves the visitor owns the mailbox (/verification,
      # /lookup, then a bearer token); nothing is shown for a claimed email.
      |> Map.put(:guest_verification_required, true)
      |> Map.put(:status_lookup_enabled, true)
      # Tickets and chats keep host parameters sent as `metadata`.
      |> Map.put(:accepts_metadata, true)

    json(conn, Map.put(settings, :widget, settings))
  end

  @doc """
  Searches published knowledge-base articles for the widget's help tab.
  Follows the customer knowledge base's settings: 404 while it is off, 403
  for an anonymous visitor while it is not public.
  """
  def search_articles(conn, params) do
    with :ok <- knowledge_base(conn),
         {:ok, term} <- search_term(params["q"]) do
      articles =
        Article.published()
        |> Article.search(term)
        |> order_by([a], desc: a.published_at, desc: a.id)
        |> limit(10)
        |> Escalated.repo().all()
        |> Enum.map(&%{title: &1.title, slug: &1.slug, excerpt: excerpt(&1.body)})

      json(conn, %{articles: articles})
    else
      error -> article_error(conn, error)
    end
  end

  @doc "One published article, by slug, for the widget's help tab. Counts the view."
  def show_article(conn, %{"slug" => slug}) do
    repo = Escalated.repo()

    with :ok <- knowledge_base(conn),
         %Article{} = article <- repo.one(where(Article.published(), [a], a.slug == ^slug)) do
      repo.update_all(where(Article, [a], a.id == ^article.id), inc: [view_count: 1])

      json(conn, %{
        title: article.title,
        slug: article.slug,
        body: article.body,
        category: category_name(article.category_id)
      })
    else
      nil -> article_error(conn, :off)
      error -> article_error(conn, error)
    end
  end

  @doc """
  OPTIONS on any widget path. Escalated.Plugs.WidgetCors answers CORS
  preflights before this runs; anything else reaching it gets an empty 204.
  """
  def preflight(conn, _params), do: send_resp(conn, 204, "")

  def create_ticket(conn, params) do
    with true <- widget_settings().enabled not in [false, nil],
         {:ok, metadata} <- WidgetMetadata.from_params(conn, params) do
      attrs = %{
        subject: params["subject"] || "Widget submission",
        description: params["description"],
        guest_name: params["name"],
        guest_email: params["email"],
        department_id: WidgetDepartments.resolve(params["department_id"]),
        # The server's own `source` wins over a host parameter of that name.
        metadata: Map.merge(metadata || %{}, %{"source" => "widget"})
      }

      case TicketService.create_guest(params, attrs) do
        {:ok, ticket, result} ->
          payload =
            GuestTicketController.guest_json(ticket)
            |> Map.merge(AccessController.public_grant(result))
            |> Map.put("message", "Ticket created.")

          conn |> put_status(201) |> json(Map.put(payload, "ticket", payload))

        {:error, reason} ->
          AccessController.error(conn, reason)
      end
    else
      false -> conn |> put_status(403) |> json(%{error: "Widget is disabled"}) |> halt()
      {:error, message} -> WidgetMetadata.invalid(conn, message)
    end
  end

  def show_ticket(conn, %{"reference" => reference} = params) do
    token = GuestAccess.token(conn, params)

    with {:ok, ticket, grant} <- GuestAccess.resolve(token),
         true <- ticket.reference == reference do
      payload = GuestTicketView.correspondence(ticket, token, grant)
      json(conn, Map.put(payload, "ticket", payload))
    else
      _ -> AccessController.error(conn, :not_found)
    end
  end

  def reply(conn, %{"reference" => reference} = params) do
    with {:ok, ticket, _} <- GuestAccess.resolve(GuestAccess.token(conn, params)),
         true <- ticket.reference == reference,
         {:ok, reply} <- TicketService.reply(ticket, %{body: params["body"], is_internal: false}) do
      conn
      |> put_status(201)
      |> json(%{reply: %{body: reply.body, created_at: reply.inserted_at}})
    else
      {:error, %Ecto.Changeset{}} -> AccessController.error(conn, :invalid)
      _ -> AccessController.error(conn, :not_found)
    end
  end

  defp knowledge_base(conn) do
    settings = GeneralSettings.all()

    cond do
      not settings["knowledge_base_enabled"] -> :off
      settings["knowledge_base_public"] or not is_nil(conn.assigns[:current_user]) -> :ok
      true -> :private
    end
  end

  defp search_term(term) when is_binary(term) do
    term = String.trim(term)

    if String.length(term) in 2..200,
      do: {:ok, term},
      else: {:invalid, "The search must be between 2 and 200 characters."}
  end

  defp search_term(_), do: {:invalid, "Enter at least 2 characters to search."}

  defp article_error(conn, :off),
    do: conn |> put_status(404) |> json(%{message: "Not found."})

  defp article_error(conn, :private),
    do: conn |> put_status(403) |> json(%{message: "The knowledge base is not public."})

  defp article_error(conn, {:invalid, message}),
    do: conn |> put_status(422) |> json(%{message: message, errors: %{q: [message]}})

  defp excerpt(nil), do: ""

  defp excerpt(body) do
    text =
      body
      |> String.replace(~r/<[^>]*>/, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    if String.length(text) > @excerpt_length,
      do: String.trim_trailing(String.slice(text, 0, @excerpt_length)) <> "...",
      else: text
  end

  defp category_name(nil), do: nil

  defp category_name(id) do
    case Escalated.repo().get(ArticleCategory, id) do
      %ArticleCategory{name: name} -> name
      nil -> nil
    end
  end

  defp widget_settings do
    Map.merge(
      %{
        enabled: true,
        title: "Contact Support",
        greeting: "How can we help you?",
        primary_color: "#4F46E5",
        fields: ~w(name email subject description),
        require_email: true
      },
      Escalated.config(:widget_settings, %{})
    )
  end
end
