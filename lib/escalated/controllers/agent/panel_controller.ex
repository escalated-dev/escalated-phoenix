defmodule Escalated.Controllers.Agent.PanelController do
  @moduledoc """
  The agent panel's own endpoints (escalated-developer-context ADR
  2026-11-05-agent-panel-data):

    * `escalated.agent.status`: the agent sets their status;
    * `escalated.agent.kb.search`: knowledge-base search for the reply
      composer;
    * `escalated.agent.notifications.index` / `.read` / `.read-all`: the
      agent's in-app notifications.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.AgentPanel
  alias Escalated.Controllers.{FormResponse, TicketDesk}
  alias Escalated.Schemas.{Article, ArticleCategory}
  alias Escalated.Services.GeneralSettings

  @kb_default_limit 10
  @kb_max_limit 20
  @excerpt_length 160

  @doc "Sets the agent's status: `{agent_status}`, or back for an Inertia visit."
  def status(conn, params) do
    status = params["status"]

    if status in AgentPanel.statuses() do
      AgentPanel.set_status(conn.assigns[:current_user], status)

      FormResponse.json_or_back(
        conn,
        %{message: "Status updated.", agent_status: status},
        "#{TicketDesk.prefix()}/agent/tickets"
      )
    else
      FormResponse.invalid(
        conn,
        %{"status" => ["The selected status is invalid."]},
        "#{TicketDesk.prefix()}/agent/tickets"
      )
    end
  end

  @doc """
  Published articles whose title or body contains `q` (2 to 200 characters),
  title matches first, then the most recently updated; `limit` 1 to 20,
  default 10. 404 while the knowledge base is off.
  """
  def kb_search(conn, params) do
    with true <- GeneralSettings.all()["knowledge_base_enabled"] == true || :kb_off,
         {:ok, term, limit} <- kb_params(params) do
      articles =
        Article
        |> Article.published()
        |> Article.search(term)
        |> Article.order_by_title_match(term)
        |> order_by([a], desc: a.updated_at, desc: a.id)
        |> limit(^limit)
        |> Escalated.repo().all()

      categories = categories(articles)
      json(conn, %{data: Enum.map(articles, &kb_item(conn, &1, categories))})
    else
      :kb_off ->
        conn |> put_status(404) |> json(%{error: "Knowledge base is not enabled"})

      {:error, errors} ->
        conn
        |> put_status(422)
        |> json(%{message: errors |> Map.values() |> hd() |> hd(), errors: errors})
    end
  end

  defp kb_params(params) do
    term = if is_binary(params["q"]), do: String.trim(params["q"]), else: ""
    length = String.length(term)
    limit = params["limit"]

    errors =
      %{}
      |> check("q", length < 2, "The q field must be at least 2 characters.")
      |> check("q", length > 200, "The q field must not be greater than 200 characters.")
      |> check("limit", not valid_limit?(limit), "The limit field must be between 1 and 20.")

    if errors == %{}, do: {:ok, term, parse_limit(limit)}, else: {:error, errors}
  end

  defp check(errors, field, true, message), do: Map.put_new(errors, field, [message])
  defp check(errors, _field, false, _message), do: errors

  defp valid_limit?(nil), do: true
  defp valid_limit?(limit), do: parse_limit(limit) in 1..@kb_max_limit

  defp parse_limit(nil), do: @kb_default_limit
  defp parse_limit(limit) when is_integer(limit), do: limit

  defp parse_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {int, ""} -> int
      _ -> 0
    end
  end

  defp parse_limit(_limit), do: 0

  defp categories(articles) do
    ids = articles |> Enum.map(& &1.category_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      from(c in ArticleCategory, where: c.id in ^ids)
      |> Escalated.repo().all()
      |> Map.new(&{&1.id, %{id: &1.id, name: &1.name}})
    end
  end

  defp kb_item(conn, article, categories) do
    %{
      id: article.id,
      title: article.title,
      excerpt: excerpt(article.body),
      url: absolute_url(conn, "#{TicketDesk.prefix()}/kb/#{article.slug}"),
      category: Map.get(categories, article.category_id),
      updated_at: article.updated_at
    }
  end

  defp excerpt(body) do
    text =
      (body || "")
      |> String.replace(~r/<[^>]*>/, " ")
      |> String.replace(~r/\s+/u, " ")
      |> String.trim()

    if String.length(text) > @excerpt_length,
      do: (text |> String.slice(0, @excerpt_length) |> String.trim_trailing()) <> "...",
      else: text
  end

  defp absolute_url(conn, path) do
    %URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port, path: path}
    |> URI.to_string()
  end

  @doc "A page of the agent's notifications, newest first."
  def notifications(conn, params) do
    with_feed(conn, fn user ->
      {items, meta} = AgentPanel.page(user, params)
      json(conn, %{data: items, meta: meta})
    end)
  end

  @doc "Marks one of the agent's notifications read: `{unread_count}`."
  def read(conn, %{"id" => id}) do
    with_feed(conn, fn user ->
      case AgentPanel.read(user, id) do
        :ok -> json(conn, %{unread_count: AgentPanel.unread_count(user)})
        :not_found -> conn |> put_status(404) |> json(%{error: "Notification not found"})
      end
    end)
  end

  @doc "Marks all the agent's notifications read: `{unread_count: 0}`."
  def read_all(conn, _params) do
    with_feed(conn, fn user ->
      AgentPanel.read_all(user)
      json(conn, %{unread_count: 0})
    end)
  end

  defp with_feed(conn, fun) do
    if AgentPanel.notifications_enabled?(),
      do: fun.(conn.assigns[:current_user]),
      else: conn |> put_status(404) |> json(%{error: "Not found"})
  end
end
