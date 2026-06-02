defmodule Escalated.Controllers.Admin.TicketSubjectController do
  @moduledoc """
  Attach and detach host-app ticket subjects via the admin API.

  Types are resolved strictly against `config :escalated, ticket_subjects: [types: ...]`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn

  alias Escalated.Schemas.TicketSubject
  alias Escalated.Services.{TicketService, TicketSubjectService}
  alias Escalated.TicketSubjects

  def create(conn, %{"reference" => reference} = params) do
    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         type when is_binary(type) <- params["type"],
         id when not is_nil(id) <- params["id"],
         :ok <- validate_api_type(type),
         :ok <- validate_subject_exists(type, to_string(id)),
         {:ok, _} <-
           TicketSubjectService.attach_subject(ticket, type, to_string(id), role: params["role"]) do
      conn
      |> put_flash(:info, "Subject attached.")
      |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      {:error, :invalid_type} ->
        conn
        |> put_status(422)
        |> json(%{errors: %{type: ["is not an allowed ticket subject."]}})

      {:error, :not_found} ->
        conn
        |> put_status(422)
        |> json(%{errors: %{id: ["No matching subject was found."]}})

      {:error, %Ecto.Changeset{} = cs} ->
        conn |> put_status(422) |> json(%{errors: format_errors(cs)})
    end
  end

  def delete(conn, %{"reference" => reference, "id" => link_id}) do
    repo = Escalated.repo()

    with ticket when not is_nil(ticket) <- TicketService.find(reference),
         %TicketSubject{} = link <- repo.get(TicketSubject, link_id),
         true <- link.ticket_id == ticket.id,
         {:ok, _} <-
           TicketSubjectService.detach_subject(ticket, link.subject_type, link.subject_id) do
      conn
      |> put_flash(:info, "Subject detached.")
      |> redirect(to: admin_ticket_path(conn, ticket))
    else
      nil ->
        conn |> put_status(404) |> json(%{error: "Ticket not found"})

      _ ->
        conn |> put_status(404) |> json(%{error: "Subject not found"})
    end
  end

  defp validate_api_type(type) when is_binary(type) do
    if TicketSubjects.api_type_allowed?(type), do: :ok, else: {:error, :invalid_type}
  end

  defp validate_api_type(_), do: {:error, :invalid_type}

  defp validate_subject_exists(type, id) do
    if TicketSubjects.resolve(type, id), do: :ok, else: {:error, :not_found}
  end

  defp admin_ticket_path(_conn, ticket) do
    prefix = Escalated.config(:route_prefix, "/support")
    "#{prefix}/admin/tickets/#{ticket.reference}"
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
