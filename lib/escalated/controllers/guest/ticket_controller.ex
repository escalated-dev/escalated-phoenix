defmodule Escalated.Controllers.Guest.TicketController do
  @moduledoc """
  The guest portal pages, `Escalated/Guest/Create` and `Escalated/Guest/Show`,
  on this package's verified guest access (see `Escalated.Services.GuestAccess`
  and docs/merchant-and-guest-access.md), with the props and routes of
  escalated-laravel's `Guest\\TicketController`:

    * `GET  {prefix}/guest/create` -- the form, with the verification and
      lookup endpoints it calls before posting.
    * `POST {prefix}/guest` -- creates the ticket from a verified form and
      redirects to its private page.
    * `GET  {prefix}/guest/:token` -- the ticket behind an expiring grant.
    * `POST {prefix}/guest/:token/reply` -- a reply as the guest.

  A ticket is only ever reached through a grant token; a bad, expired or
  revoked one is a 404.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.{TicketPresenter, UIRenderer}
  alias Escalated.Schemas.{Department, Ticket}
  alias Escalated.Services.{GuestAccess, TicketService}

  def create(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Guest/Create", %{
      departments:
        Escalated.repo().all(Department.active() |> Department.ordered())
        |> Enum.map(&%{id: &1.id, name: &1.name}),
      priorities: Ticket.priorities(),
      verification_url: guest_path("/verification"),
      lookup_url: guest_path("/lookup")
    })
  end

  def store(conn, params) do
    attrs = %{
      subject: params["subject"],
      description: params["description"],
      guest_name: params["guest_name"],
      guest_email: params["guest_email"],
      priority: present(params["priority"]) || "medium",
      department_id: present(params["department_id"])
    }

    case TicketService.create_guest(params, attrs) do
      {:ok, _ticket, result} ->
        conn
        |> put_flash(:info, "Your ticket has been submitted.")
        |> redirect(to: guest_path("/" <> result["guest_access_token"]))

      {:error, %Ecto.Changeset{} = changeset} ->
        FormResponse.invalid(conn, changeset, guest_path("/create"))

      {:error, reason} ->
        FormResponse.invalid(conn, %{verification_code: [message(reason)]}, guest_path("/create"))
    end
  end

  def show(conn, %{"token" => token}) do
    case GuestAccess.resolve(token) do
      {:ok, ticket, grant} ->
        payload =
          ticket
          |> TicketPresenter.customer_detail(
            attachment_url: &GuestAccess.attachment_url(&1, token, grant)
          )
          |> Map.put(:guest_access_expires_at, DateTime.to_iso8601(grant.expires_at))

        UIRenderer.render_page(conn, "Escalated/Guest/Show", %{ticket: payload, token: token})

      _ ->
        not_found(conn)
    end
  end

  def reply(conn, %{"token" => token} = params) do
    case GuestAccess.resolve(token) do
      {:ok, %Ticket{status: "closed"}, _grant} ->
        conn
        |> put_flash(:error, "This ticket is closed. Open a new ticket to contact us again.")
        |> redirect(to: guest_path("/" <> token))

      {:ok, ticket, _grant} ->
        case TicketService.reply(ticket, %{body: params["body"], is_internal: false}) do
          {:ok, _reply} ->
            conn |> put_flash(:info, "Reply sent.") |> redirect(to: guest_path("/" <> token))

          {:error, changeset} ->
            FormResponse.invalid(conn, changeset, guest_path("/" <> token))
        end

      _ ->
        not_found(conn)
    end
  end

  defp message(:verification),
    do: "This code is invalid, expired or already used. Request a new code."

  defp message(:rate_limited), do: "Please wait before requesting another code."
  defp message(:unavailable), do: "Guest verification is temporarily unavailable."
  defp message(_), do: "Check the submitted details."

  defp present(value) when value in [nil, ""], do: nil
  defp present(value), do: value

  defp not_found(conn), do: conn |> put_status(404) |> json(%{message: "Not found."})

  defp guest_path(suffix), do: Escalated.config(:route_prefix, "/support") <> "/guest" <> suffix
end
