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

  alias Escalated.Schemas.{SatisfactionRating, Ticket}
  alias Escalated.Services.TicketService

  def store(conn, %{"reference" => reference} = params) do
    user = conn.assigns[:current_user]

    rated_by = %{
      rated_by_type: user && to_string(Escalated.user_schema()),
      rated_by_id: user && user.id
    }

    submit_rating(conn, TicketService.find(reference), params, rated_by)
  end

  def store_guest(conn, %{"token" => token} = params) do
    ticket = Escalated.repo().get_by(Ticket, guest_token: token)
    submit_rating(conn, ticket, params, %{})
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
