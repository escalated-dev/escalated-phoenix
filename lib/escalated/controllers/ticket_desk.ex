defmodule Escalated.Controllers.TicketDesk do
  @moduledoc """
  What the agent and admin ticket pages share: the props both show pages and
  both queues send, and the writes both pages post that the two desks handle
  identically (follow, macro, pin, presence).

  The admin and agent controllers delegate to these with their own scope so
  each answers on its own routes (`escalated.admin.tickets.*`,
  `escalated.agent.tickets.*`), the way escalated-laravel's two
  `TicketController`s do.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [put_flash: 3, redirect: 2, json: 2]
  import Ecto.Query, only: [from: 2]

  alias Escalated.Rendering.{Paginator, TicketPresenter, UserDirectory}
  alias Escalated.Schemas.{CannedResponse, Department, Macro, Reply, Tag}
  alias Escalated.Services.{Followers, MacroService, SavedViewService, TicketService}

  @filter_keys ~w(status priority department_id assigned_to search unassigned sla_breached ticket_type account_type account_id)

  @doc "The ticket queue as a paginator of rows, plus the filters sent back."
  def queue_props(conn, params, scope) do
    tickets = TicketService.list(atomize_filters(params))
    path = "#{prefix()}/#{scope}/tickets"

    %{
      tickets: Paginator.paginate(tickets, params, path) |> present_page(),
      filters: params,
      departments: departments(),
      tags: tags()
    }
    |> Map.merge(queue_extras(conn, scope))
  end

  defp present_page(%{data: tickets} = page), do: %{page | data: TicketPresenter.rows(tickets)}

  defp queue_extras(conn, "admin") do
    user = conn.assigns[:current_user]

    %{
      agents: UserDirectory.agents(),
      savedViews: Enum.map(SavedViewService.list_for_user(user.id), &saved_view/1)
    }
  end

  defp queue_extras(_conn, _scope), do: %{}

  @doc "The props both ticket pages read, apart from the scope-specific ones."
  def show_props(conn, ticket) do
    user_id = conn.assigns[:current_user].id

    %{
      ticket: TicketPresenter.staff_detail(ticket),
      departments: departments(),
      tags: tags(),
      cannedResponses: canned_responses(user_id),
      macros: macros(user_id),
      is_following: Followers.following?(ticket.id, user_id),
      followers_count: Followers.count(ticket.id)
    }
  end

  @doc "Follow the ticket, or stop following it."
  def follow(conn, %{"reference" => reference}, scope) do
    with_ticket(conn, reference, fn ticket ->
      message =
        case Followers.toggle(ticket.id, conn.assigns[:current_user].id) do
          :followed -> "You are now following this ticket."
          :unfollowed -> "You are no longer following this ticket."
        end

      conn |> put_flash(:info, message) |> redirect(to: ticket_path(scope, ticket))
    end)
  end

  @doc "Apply a macro the user may see to the ticket."
  def apply_macro(conn, %{"reference" => reference} = params, scope) do
    user_id = conn.assigns[:current_user].id

    with_ticket(conn, reference, fn ticket ->
      macro =
        case Integer.parse(to_string(params["macro_id"])) do
          {id, ""} -> scoped_repo().one(from(m in Macro.for_agent(user_id), where: m.id == ^id))
          _ -> nil
        end

      case macro do
        nil ->
          conn |> put_status(404) |> json(%{error: "Macro not found"})

        macro ->
          MacroService.apply(Escalated.repo(), macro, ticket, user_id)

          conn
          |> put_flash(:info, "Macro \"#{macro.name}\" applied.")
          |> redirect(to: ticket_path(scope, ticket))
      end
    end)
  end

  @doc "Pin a reply on the ticket, or unpin it."
  def pin(conn, %{"reference" => reference, "reply_id" => reply_id}, scope) do
    with_ticket(conn, reference, fn ticket ->
      reply =
        case Integer.parse(to_string(reply_id)) do
          {id, ""} ->
            Escalated.repo().one(
              from(r in Reply, where: r.id == ^id and r.ticket_id == ^ticket.id)
            )

          _ ->
            nil
        end

      case reply do
        nil ->
          conn |> put_status(404) |> json(%{error: "Reply not found"})

        reply ->
          reply |> Reply.changeset(%{is_pinned: !reply.is_pinned}) |> Escalated.repo().update!()

          conn
          |> put_flash(:info, if(reply.is_pinned, do: "Note unpinned.", else: "Note pinned."))
          |> redirect(to: ticket_path(scope, ticket))
      end
    end)
  end

  @doc "Record the viewer and answer the other people on the ticket."
  def presence(conn, %{"reference" => reference}) do
    user = conn.assigns[:current_user]

    with_ticket(conn, reference, fn ticket ->
      viewer = %{id: user.id, name: Map.get(user, :name) || Map.get(user, :email)}
      json(conn, %{viewers: Escalated.Presence.heartbeat(ticket.id, viewer)})
    end)
  end

  @doc "The ticket page path for a desk."
  def ticket_path(scope, ticket), do: "#{prefix()}/#{scope}/tickets/#{ticket.reference}"

  defp with_ticket(conn, reference, fun) do
    case TicketService.find(reference) do
      nil -> conn |> put_status(404) |> json(%{error: "Ticket not found"})
      ticket -> fun.(ticket)
    end
  end

  defp departments do
    Escalated.repo().all(Department.active() |> Department.ordered())
    |> Enum.map(&%{id: &1.id, name: &1.name})
  end

  defp tags do
    Escalated.repo().all(Tag.ordered()) |> Enum.map(&%{id: &1.id, name: &1.name, color: &1.color})
  end

  defp canned_responses(user_id) do
    CannedResponse.for_agent(user_id)
    |> scoped_repo().all()
    |> Enum.map(fn c ->
      %{id: c.id, title: c.title, body: c.body, category: c.category, is_shared: c.is_shared}
    end)
  end

  defp macros(user_id) do
    Macro.for_agent(user_id)
    |> scoped_repo().all()
    |> Enum.map(&%{id: &1.id, name: &1.name, description: &1.description, actions: &1.actions})
  end

  defp saved_view(view) do
    %{
      id: view.id,
      name: view.name,
      filters: view.filters,
      is_shared: view.is_shared,
      position: view.position,
      user_id: view.user_id
    }
  end

  defp scoped_repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())

  defp prefix, do: Escalated.config(:route_prefix, "/support")

  @doc false
  def atomize_filters(params) do
    params
    |> Map.take(@filter_keys)
    |> Enum.reduce(%{}, fn
      {_key, ""}, acc -> acc
      {_key, nil}, acc -> acc
      {"unassigned", "true"}, acc -> Map.put(acc, :unassigned, true)
      {"sla_breached", "true"}, acc -> Map.put(acc, :sla_breached, true)
      {key, val}, acc -> Map.put(acc, String.to_existing_atom(key), val)
    end)
  end
end
