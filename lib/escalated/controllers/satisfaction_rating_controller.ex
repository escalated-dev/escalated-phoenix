defmodule Escalated.Controllers.SatisfactionRatingController do
  @moduledoc """
  CSAT submission for customers (by ticket reference) and guests (by
  guest token). Mirrors the Laravel `SatisfactionRatingController`: a
  ticket can be rated exactly once, and only once it is resolved or
  closed.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.SatisfactionRating
  alias Escalated.Services.TicketService
  alias Escalated.TicketAccess

  def store(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]
    ticket = TicketService.find(reference)

    cond do
      is_nil(TicketAccess.user_id(user)) ->
        conn |> put_status(401) |> Phoenix.Controller.json(%{error: "Authentication required"})

      is_nil(ticket) ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      not TicketAccess.requester?(ticket, user) ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{error: "You can only rate your own tickets"})

      true ->
        submit_rating(conn, ticket, params, %{
          rated_by_type: to_string(Escalated.user_schema()),
          rated_by_id: TicketAccess.user_id(user)
        })
    end
  end

  def store_guest(conn, %{"token" => token} = params) when is_binary(token) and token != "" do
    case Escalated.Services.GuestAccess.resolve(token) do
      {:ok, ticket, _grant} -> submit_rating(conn, ticket, params, %{})
      _ -> conn |> put_status(404) |> json(%{error: "Ticket not found"})
    end
  end

  def store_guest(conn, _params) do
    conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})
  end

  defp submit_rating(conn, ticket, params, rated_by) do
    cond do
      is_nil(ticket) ->
        conn |> put_status(404) |> Phoenix.Controller.json(%{error: "Ticket not found"})

      ticket.status not in ["resolved", "closed"] ->
        conn
        |> put_status(422)
        |> Phoenix.Controller.json(%{error: "Only resolved or closed tickets can be rated."})

      already_rated?(ticket) ->
        conn
        |> put_status(422)
        |> Phoenix.Controller.json(%{error: "This ticket has already been rated."})

      true ->
        create_rating(conn, ticket, params, rated_by)
    end
  end

  defp already_rated?(ticket) do
    Escalated.repo().exists?(from(r in SatisfactionRating, where: r.ticket_id == ^ticket.id))
  end

  defp create_rating(conn, ticket, params, rated_by) do
    attrs =
      Map.merge(
        %{ticket_id: ticket.id, rating: params["rating"], comment: params["comment"]},
        rated_by
      )

    %SatisfactionRating{}
    |> SatisfactionRating.changeset(attrs)
    |> Escalated.repo().insert()
    |> case do
      {:ok, _rating} ->
        conn
        |> put_status(201)
        |> Phoenix.Controller.json(%{ok: true, message: "Thanks for your feedback."})

      {:error, changeset} ->
        conn |> put_status(422) |> Phoenix.Controller.json(%{errors: format_errors(changeset)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
