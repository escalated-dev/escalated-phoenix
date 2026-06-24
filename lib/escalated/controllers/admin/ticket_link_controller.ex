defmodule Escalated.Controllers.Admin.TicketLinkController do
  @moduledoc """
  List, create, and remove typed links between tickets. Mirrors the
  Laravel `TicketLinkController` (self-link and duplicate guards; links
  are matched in either direction).
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{Ticket, TicketLink}
  alias Escalated.Services.TicketService

  def index(conn, %{"reference" => reference}) do
    case TicketService.find(reference) do
      nil -> conn |> put_status(404) |> json(%{error: "Ticket not found"})
      ticket -> json(conn, %{links: links_for(ticket)})
    end
  end

  def create(conn, %{"reference" => reference} = params) do
    repo = Escalated.repo()

    case validate_link(reference, params) do
      {:ok, ticket, parent_id, child_id, link_type} ->
        {:ok, _} = insert_link(repo, parent_id, child_id, link_type)

        conn
        |> put_flash(:info, "Ticket linked successfully.")
        |> redirect(to: ticket_path(ticket))

      {:error, :ticket_not_found} ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      {:error, message} ->
        conn |> put_status(422) |> json(%{error: message})
    end
  end

  def delete(conn, %{"reference" => reference, "id" => id}) do
    repo = Escalated.repo()

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         %TicketLink{} = link <- repo.get(TicketLink, id),
         true <- link.parent_ticket_id == ticket.id or link.child_ticket_id == ticket.id do
      repo.delete(link)
      conn |> put_flash(:info, "Ticket link removed.") |> redirect(to: ticket_path(ticket))
    else
      _ -> conn |> put_status(404) |> json(%{error: "Ticket link not found"})
    end
  end

  defp validate_link(reference, params) do
    repo = Escalated.repo()
    ticket = TicketService.find(reference)
    target = params["target_reference"] && TicketService.find(params["target_reference"])
    link_type = params["link_type"]

    cond do
      is_nil(ticket) ->
        {:error, :ticket_not_found}

      link_type not in TicketLink.link_types() ->
        {:error, "Invalid link type."}

      is_nil(target) ->
        {:error, "Target ticket not found."}

      target.id == ticket.id ->
        {:error, "Cannot link a ticket to itself."}

      linked?(repo, ticket.id, target.id, link_type) ->
        {:error, "These tickets are already linked."}

      true ->
        {:ok, ticket, ticket.id, target.id, link_type}
    end
  end

  defp linked?(repo, a_id, b_id, link_type) do
    repo.exists?(
      from(l in TicketLink,
        where:
          l.link_type == ^link_type and
            ((l.parent_ticket_id == ^a_id and l.child_ticket_id == ^b_id) or
               (l.parent_ticket_id == ^b_id and l.child_ticket_id == ^a_id))
      )
    )
  end

  defp insert_link(repo, parent_id, child_id, link_type) do
    %TicketLink{}
    |> TicketLink.changeset(%{
      parent_ticket_id: parent_id,
      child_ticket_id: child_id,
      link_type: link_type
    })
    |> repo.insert()
  end

  defp links_for(ticket) do
    repo = Escalated.repo()

    links =
      repo.all(
        from(l in TicketLink,
          where: l.parent_ticket_id == ^ticket.id or l.child_ticket_id == ^ticket.id
        )
      )

    tickets_by_id = preload_linked_tickets(repo, links)
    Enum.map(links, &link_json(&1, ticket, tickets_by_id))
  end

  defp preload_linked_tickets(repo, links) do
    ids = links |> Enum.flat_map(&[&1.parent_ticket_id, &1.child_ticket_id]) |> Enum.uniq()

    from(t in Ticket, where: t.id in ^ids)
    |> repo.all()
    |> Map.new(&{&1.id, &1})
  end

  defp link_json(link, ticket, tickets_by_id) do
    {direction, other_id} =
      if link.parent_ticket_id == ticket.id,
        do: {"parent", link.child_ticket_id},
        else: {"child", link.parent_ticket_id}

    %{
      id: link.id,
      link_type: link.link_type,
      direction: direction,
      ticket: ticket_summary(Map.get(tickets_by_id, other_id))
    }
  end

  defp ticket_summary(nil), do: nil

  defp ticket_summary(%Ticket{} = t) do
    %{id: t.id, reference: t.reference, subject: t.subject, status: t.status}
  end

  defp ticket_path(ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/tickets/#{ticket.reference}"
  end
end
