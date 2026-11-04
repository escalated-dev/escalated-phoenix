defmodule Escalated.Controllers.AgentInbox do
  @moduledoc """
  The agent panel's optional `inbox` and `queue` props (shared frontend
  `docs/agent-panel.md`), after escalated-laravel's `AgentInbox`.

  Every number is a count over the same filters the ticket list applies
  (`Escalated.Services.TicketService.count/1`), through the ticket visibility
  scope, so it is what the agent would see by opening that list. Rail counts
  (`counts`, `views`) are of unresolved, unsnoozed tickets unless a view's
  filters name a status; `stats` are for the current queue.

  The counts are not cached: this package has no cache of its own, and each
  list request runs a bounded number of count queries (3 counts, 5 built-in
  views, 4 stats and one per saved view, up to 50 saved views).
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Controllers.TicketDesk
  alias Escalated.Schemas.SavedView
  alias Escalated.Services.TicketService

  @session_key "escalated_agent_inbox_queue"

  @max_saved_views 50

  # The query keys the agent ticket list reads.
  @list_keys ~w(status priority ticket_type assigned assigned_to unassigned department_id
                account_type account_id search sla_breached sla_at_risk resolved_today open
                updated_within_hours sort_by sort_dir page per_page view)

  # Keys that pick a page, never which tickets are in a queue.
  @presentation_keys ~w(page per_page view)

  @flags ~w(open sla_at_risk resolved_today)

  @queue_titles %{"mine" => "My inbox", "unassigned" => "Unassigned", "all" => "All tickets"}

  @built_in_names %{
    "urgent" => "Urgent",
    "sla_at_risk" => "SLA at risk",
    "waiting_on_me" => "Waiting on me",
    "waiting_on_customer" => "Waiting on customer",
    "recently_updated" => "Recently updated"
  }

  @doc """
  Checks the filters added for the agent panel: `open`, `sla_at_risk` and
  `resolved_today` are booleans, `updated_within_hours` an integer from 1 to
  8760. Returns `:ok` or `{:error, %{field => [message]}}`.
  """
  def validate(params) do
    errors =
      Enum.reduce(@flags, %{}, fn key, acc ->
        if blank?(params[key]) or boolean?(params[key]),
          do: acc,
          else: Map.put(acc, key, ["The #{key} field must be true or false."])
      end)

    errors =
      case params["updated_within_hours"] do
        value when value in [nil, ""] ->
          errors

        value ->
          case Integer.parse(to_string(value)) do
            {hours, ""} when hours >= 1 and hours <= 8760 ->
              errors

            _ ->
              Map.put(errors, "updated_within_hours", [
                "The updated_within_hours field must be an integer between 1 and 8760."
              ])
          end
      end

    if errors == %{}, do: :ok, else: {:error, errors}
  end

  @doc "The list's filters from `params`, with `assigned=me` and `assigned_to=me` as the agent's id."
  def normalise(params, agent) do
    params
    |> Map.take(@list_keys)
    |> normalise_assignee(agent)
  end

  @doc """
  The queue a list request shows: `%{key, title, filters}`, where `filters`
  are the queue's own (what its counts and stats are over).
  """
  def queue_for(filters, agent) do
    views = views(agent)

    by_id =
      if blank?(filters["view"]),
        do: nil,
        else: Enum.find(views, &(to_string(&1.id) == to_string(filters["view"])))

    selection = comparable(filters)

    by_filters =
      selection != %{} &&
        Enum.find(views, &(&1.filters != %{} and comparable(&1.filters) == selection))

    cond do
      by_id -> view_queue(by_id)
      by_filters -> view_queue(by_filters)
      to_string(filters["assigned_to"]) == to_string(agent.id) -> workspace_queue("mine", agent)
      TicketDesk.flag?(filters["unassigned"] || "") -> workspace_queue("unassigned", agent)
      true -> workspace_queue("all", agent)
    end
  end

  @doc "The filters the list applies: the request's, over a view picked by id."
  def list_filters(filters, %{key: "view:" <> _} = queue) do
    if blank?(filters["view"]),
      do: filters,
      else: Map.merge(queue.filters, Map.delete(filters, "view"))
  end

  def list_filters(filters, _queue), do: filters

  @doc "Remembers the queue for the ticket page, which is opened from the list."
  def remember(conn, queue) do
    if session?(conn), do: Plug.Conn.put_session(conn, @session_key, queue.key), else: conn
  end

  @doc "The queue last shown in the list, or All tickets."
  def recalled(conn, agent) do
    key = if session?(conn), do: Plug.Conn.get_session(conn, @session_key)

    case key do
      "view:" <> id ->
        # The view may have been deleted or unshared since.
        case Enum.find(views(agent), &(to_string(&1.id) == id)) do
          nil -> workspace_queue("all", agent)
          view -> view_queue(view)
        end

      key when is_binary(key) ->
        workspace_queue(key, agent)

      _ ->
        workspace_queue("all", agent)
    end
  end

  @doc "The `queue` prop."
  def queue_prop(queue), do: %{key: queue.key, title: queue.title}

  @doc "The `inbox` prop for this agent and queue."
  def inbox(agent, queue) do
    base = queue.filters

    %{
      counts: %{
        mine: count_open(%{"assigned_to" => agent.id}),
        unassigned: count_open(%{"unassigned" => 1}),
        all: count_open(%{})
      },
      views:
        Enum.map(views(agent), fn view ->
          %{id: view.id, name: view.name, count: count_open(view.filters), filters: view.filters}
        end),
      # Each stat is the list the tile opens: the queue plus the tile's filters.
      stats: %{
        open: count(Map.put(base, "status", "open")),
        urgent: count(Map.merge(base, %{"priority" => "urgent", "open" => 1})),
        sla_at_risk: count(Map.put(base, "sla_at_risk", 1)),
        resolved_today: count(Map.merge(base, %{"status" => "resolved", "resolved_today" => 1}))
      }
    }
  end

  @doc "Built-in views, then the agent's own and shared saved views, by position."
  def views(agent) do
    me = agent.id

    built_in = [
      {"urgent", %{"priority" => "urgent", "open" => 1}},
      {"sla_at_risk", %{"sla_at_risk" => 1}},
      {"waiting_on_me", %{"assigned_to" => me, "status" => "waiting_on_agent"}},
      {"waiting_on_customer", %{"assigned_to" => me, "status" => "waiting_on_customer"}},
      {"recently_updated",
       %{"open" => 1, "updated_within_hours" => 24, "sort_by" => "updated_at"}}
    ]

    saved =
      from(v in SavedView.accessible_by(me),
        order_by: [asc: v.position, asc: v.id],
        limit: @max_saved_views
      )
      |> Escalated.repo().all()

    Enum.map(built_in, fn {id, filters} ->
      %{id: id, name: Map.fetch!(@built_in_names, id), filters: filters}
    end) ++
      Enum.map(saved, fn view ->
        %{id: view.id, name: view.name, filters: normalise_assignee(view.filters || %{}, agent)}
      end)
  end

  defp view_queue(view), do: %{key: "view:#{view.id}", title: view.name, filters: view.filters}

  defp workspace_queue("mine", agent),
    do: %{key: "mine", title: @queue_titles["mine"], filters: %{"assigned_to" => agent.id}}

  defp workspace_queue("unassigned", _agent),
    do: %{key: "unassigned", title: @queue_titles["unassigned"], filters: %{"unassigned" => 1}}

  defp workspace_queue(_key, _agent),
    do: %{key: "all", title: @queue_titles["all"], filters: %{}}

  # Unresolved, unsnoozed tickets, unless the filters ask for a status themselves.
  defp count_open(filters) do
    if blank?(filters["status"]), do: count(Map.put(filters, "open", 1)), else: count(filters)
  end

  defp count(filters), do: filters |> TicketDesk.atomize_filters() |> TicketService.count()

  defp normalise_assignee(filters, agent) do
    filters = Map.new(filters, fn {key, value} -> {to_string(key), value} end)

    filters =
      if filters["assigned"] == "me" or filters["assigned_to"] == "me",
        do: Map.put(filters, "assigned_to", agent.id),
        else: filters

    Map.delete(filters, "assigned")
  end

  # Filters as strings, without empty values or order, for comparing a URL with a view.
  defp comparable(filters) do
    filters
    |> Enum.reject(fn {key, value} ->
      value in ["", nil, false] or to_string(key) in @presentation_keys
    end)
    |> Map.new(fn
      {key, value} when is_list(value) ->
        {to_string(key), value |> Enum.map(&to_string/1) |> Enum.sort() |> Enum.join(",")}

      {key, true} ->
        {to_string(key), "1"}

      {key, value} ->
        {to_string(key), to_string(value)}
    end)
  end

  defp session?(conn), do: Map.get(conn.private, :plug_session_fetch) == :done

  defp blank?(value), do: value in [nil, ""]

  defp boolean?(value), do: to_string(value) in ~w(0 1 true false)
end
