defmodule Escalated.Controllers.Admin.StatusController do
  @moduledoc """
  Admin CRUD over custom ticket statuses, serving
  `Escalated/Admin/Statuses/Index` and `Escalated/Admin/Statuses/Form` with
  the props escalated-laravel's `Admin\\StatusController` sends.

  System rows (the built-in statuses) are listed and editable, but their slug
  and category are fixed and they cannot be deleted. Deleting a custom status
  clears it from its tickets, which keep their built-in status. Changing a
  status's category does not move the tickets already in it.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{Ticket, TicketStatus}
  alias Escalated.Services.TicketStatusService

  def index(conn, _params) do
    TicketStatusService.ensure_system_statuses()

    UIRenderer.render_page(conn, "Escalated/Admin/Statuses/Index", %{
      statuses: Enum.map(TicketStatusService.list(), &TicketStatusService.status_json/1),
      categories: TicketStatus.categories()
    })
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Statuses/Form", %{
      categories: TicketStatus.categories()
    })
  end

  def edit(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      status ->
        UIRenderer.render_page(conn, "Escalated/Admin/Statuses/Form", %{
          status: TicketStatusService.status_json(status),
          categories: TicketStatus.categories()
        })
    end
  end

  def create(conn, params) do
    with {:ok, attrs} <- form_attrs(params),
         attrs = Map.put(attrs, :slug, TicketStatusService.unique_slug(attrs.label)),
         {:ok, _} <- save(%TicketStatus{}, attrs) do
      conn |> put_flash(:info, "Status created.") |> redirect(to: index_path())
    else
      {:error, errors} -> FormResponse.invalid(conn, errors, index_path() <> "/create")
    end
  end

  def update(conn, %{"id" => id} = params) do
    with status when not is_nil(status) <- find(id),
         {:ok, attrs} <- form_attrs(params),
         {:ok, _} <- save(status, attrs) do
      conn |> put_flash(:info, "Status updated.") |> redirect(to: index_path())
    else
      nil -> not_found(conn)
      {:error, errors} -> FormResponse.invalid(conn, errors, "#{index_path()}/#{id}/edit")
    end
  end

  def delete(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      %TicketStatus{is_system: true} ->
        conn
        |> put_flash(:error, "System statuses cannot be deleted.")
        |> FormResponse.invalid(
          %{"status" => ["System statuses cannot be deleted."]},
          index_path()
        )

      status ->
        # Its tickets keep their built-in status and lose the custom one
        # (no foreign key enforces this, so it is done here).
        repo().transaction(fn ->
          from(t in Ticket, where: t.ticket_status_id == ^status.id)
          |> repo().update_all(set: [ticket_status_id: nil])

          repo().delete!(status)
        end)

        conn |> put_flash(:info, "Status deleted.") |> redirect(to: index_path())
    end
  end

  # Private

  # Saves the row and, when it is the default, clears is_default on the other
  # rows of its category.
  defp save(status, attrs) do
    repo().transaction(fn ->
      case status |> TicketStatus.changeset(attrs) |> repo().insert_or_update() do
        {:ok, saved} ->
          if saved.is_default do
            from(s in TicketStatus,
              where: s.category == ^saved.category and s.id != ^saved.id and s.is_default
            )
            |> repo().update_all(set: [is_default: false])
          end

          saved

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  # Laravel's rules: label required (max 255), category one of the five,
  # color required (max 20), description nullable, position an integer,
  # is_default a boolean.
  defp form_attrs(params) do
    label = trimmed(params["label"])
    color = trimmed(params["color"])
    position = integer(params["position"])
    is_default = boolean(params["is_default"])

    errors =
      []
      |> add_if(label in [nil, ""], "label", "The label field is required.")
      |> add_if(
        is_binary(label) and String.length(label) > 255,
        "label",
        "The label may not be greater than 255 characters."
      )
      |> add_if(
        params["category"] not in TicketStatus.categories(),
        "category",
        "The selected category is invalid."
      )
      |> add_if(color in [nil, ""], "color", "The color field is required.")
      |> add_if(
        is_binary(color) and String.length(color) > 20,
        "color",
        "The color may not be greater than 20 characters."
      )
      |> add_if(
        not (is_nil(params["description"]) or is_binary(params["description"])),
        "description",
        "The description must be a string."
      )
      |> add_if(position == :error, "position", "The position must be an integer.")
      |> add_if(is_default == :error, "is_default", "The is default field must be true or false.")
      |> Map.new(fn {k, v} -> {k, [v]} end)

    if errors == %{} do
      {:ok,
       %{
         label: label,
         category: params["category"],
         color: color,
         description: blank_to_nil(params["description"]),
         position: position || 0,
         is_default: is_default || false
       }}
    else
      {:error, errors}
    end
  end

  defp add_if(errors, true, key, message) do
    if List.keymember?(errors, key, 0), do: errors, else: errors ++ [{key, message}]
  end

  defp add_if(errors, _, _key, _message), do: errors

  defp integer(nil), do: nil
  defp integer(""), do: nil
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> :error
    end
  end

  defp integer(_), do: :error

  defp boolean(nil), do: nil
  defp boolean(value) when value in [true, 1, "1", "true", "on"], do: true
  defp boolean(value) when value in [false, 0, "0", "false", "off", ""], do: false
  defp boolean(_), do: :error

  defp trimmed(value) when is_binary(value), do: String.trim(value)
  defp trimmed(_), do: nil

  defp blank_to_nil(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp blank_to_nil(_), do: nil

  defp find(id) do
    case integer(to_string(id)) do
      int when is_integer(int) -> repo().get(TicketStatus, int)
      _ -> nil
    end
  end

  defp not_found(conn),
    do: conn |> put_status(404) |> json(%{error: "Status not found"})

  defp repo, do: Escalated.repo()

  defp index_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/statuses"
end
