defmodule Escalated.Controllers.Admin.AuditLogController do
  @moduledoc """
  The audit log screen, `Escalated/Admin/AuditLog/Index`, with the props
  escalated-laravel's `AuditLogController` sends: `logs` (a paginator, 50 a
  page, newest first), `filters`, `users`, `actions` and `resourceTypes`.

  Filters: `user_id`, `action`, `auditable_type`, `date_from` and `date_to`
  (dates, inclusive). This backend stores the audited record as
  `entity_type`/`entity_id` and the actor as `performer_id`; the page's
  `auditable_*` and `user` are mapped from those. `users` lists the people
  who appear in the log, so the filter offers only names that match something.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Ecto.Query

  alias Escalated.Rendering.{Paginator, UIRenderer, UserDirectory}
  alias Escalated.Schemas.AuditLog

  @filters ~w(user_id action auditable_type date_from date_to)

  def index(conn, params) do
    repo = Escalated.Tenancy.scoped_repo(Escalated.repo())
    path = Escalated.config(:route_prefix, "/support") <> "/admin/audit-log"

    page =
      Paginator.paginate_query(filtered(params), repo, Map.put(params, "per_page", "50"), path)

    directory = UserDirectory.lookup(Enum.map(page.data, & &1.performer_id))
    page = %{page | data: Enum.map(page.data, &log_json(&1, directory))}

    users =
      from(l in AuditLog,
        where: not is_nil(l.performer_id),
        distinct: true,
        select: l.performer_id
      )
      |> repo.all()
      |> UserDirectory.lookup()
      |> Map.values()
      |> Enum.map(&%{id: &1.id, name: &1.name})
      |> Enum.sort_by(&String.downcase(to_string(&1.name)))

    UIRenderer.render_page(conn, "Escalated/Admin/AuditLog/Index", %{
      logs: page,
      filters: Map.take(params, @filters),
      users: users,
      actions: distinct_values(repo, :action),
      resourceTypes: distinct_values(repo, :entity_type)
    })
  end

  defp filtered(params) do
    from(l in AuditLog, order_by: [desc: l.inserted_at, desc: l.id])
    |> filter(:performer_id, params["user_id"])
    |> filter(:action, params["action"])
    |> filter(:entity_type, params["auditable_type"])
    |> since(parse_date(params["date_from"]))
    |> until(parse_date(params["date_to"]))
  end

  defp filter(query, _field, value) when value in [nil, ""], do: query
  defp filter(query, field, value), do: where(query, [l], field(l, ^field) == ^value)

  defp since(query, nil), do: query

  defp since(query, date),
    do: where(query, [l], l.inserted_at >= ^DateTime.new!(date, ~T[00:00:00], "Etc/UTC"))

  defp until(query, nil), do: query

  defp until(query, date),
    do: where(query, [l], l.inserted_at <= ^DateTime.new!(date, ~T[23:59:59], "Etc/UTC"))

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp distinct_values(repo, field) do
    from(l in AuditLog,
      where: not is_nil(field(l, ^field)),
      distinct: true,
      select: field(l, ^field),
      order_by: field(l, ^field)
    )
    |> repo.all()
  end

  defp log_json(log, directory) do
    %{
      id: log.id,
      action: log.action,
      auditable_type: log.entity_type,
      auditable_id: log.entity_id,
      user_id: log.performer_id,
      user: UserDirectory.get(directory, log.performer_id),
      old_values: log.old_values,
      new_values: log.new_values,
      ip_address: log.ip_address,
      created_at: log.inserted_at && DateTime.to_iso8601(log.inserted_at)
    }
  end
end
