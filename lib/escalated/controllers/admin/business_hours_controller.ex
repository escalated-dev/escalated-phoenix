defmodule Escalated.Controllers.Admin.BusinessHoursController do
  @moduledoc """
  Admin CRUD over business schedules and their holidays, serving
  `Escalated/Admin/BusinessHours/Index` and `Escalated/Admin/BusinessHours/Form`
  with the props escalated-laravel's `Admin\\BusinessHoursController` sends.

  SLA deadlines count against these schedules when business hours apply; see
  `Escalated.Services.SlaService.business_schedule_for/2`.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{BusinessSchedule, Department, Holiday, SlaPolicy}

  @days ~w(monday tuesday wednesday thursday friday saturday sunday)

  def index(conn, _params) do
    schedules =
      from(s in BusinessSchedule, order_by: [asc: s.id], preload: [:holidays])
      |> repo().all()
      |> Enum.map(&schedule_json/1)

    UIRenderer.render_page(conn, "Escalated/Admin/BusinessHours/Index", %{schedules: schedules})
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/BusinessHours/Form", %{
      timezones: Escalated.Timezones.identifiers()
    })
  end

  def edit(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      schedule ->
        UIRenderer.render_page(conn, "Escalated/Admin/BusinessHours/Form", %{
          schedule: schedule_json(schedule),
          timezones: Escalated.Timezones.identifiers()
        })
    end
  end

  def create(conn, params) do
    case save(%BusinessSchedule{}, params) do
      {:ok, _} ->
        conn |> put_flash(:info, "Business schedule created.") |> redirect(to: index_path())

      {:error, errors} ->
        FormResponse.invalid(conn, errors, index_path() <> "/create")
    end
  end

  def update(conn, %{"id" => id} = params) do
    case find(id) do
      nil ->
        not_found(conn)

      schedule ->
        case save(schedule, params) do
          {:ok, _} ->
            conn |> put_flash(:info, "Business schedule updated.") |> redirect(to: index_path())

          {:error, errors} ->
            FormResponse.invalid(conn, errors, "#{index_path()}/#{id}/edit")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case find(id) do
      nil ->
        not_found(conn)

      schedule ->
        {:ok, _} =
          repo().transaction(fn ->
            # Policies and departments fall back to the next schedule in line.
            for schema <- [SlaPolicy, Department] do
              from(r in schema, where: r.business_schedule_id == ^schedule.id)
              |> repo().update_all(set: [business_schedule_id: nil])
            end

            from(h in Holiday, where: h.business_schedule_id == ^schedule.id)
            |> repo().delete_all()

            repo().delete!(schedule)
          end)

        conn |> put_flash(:info, "Business schedule deleted.") |> redirect(to: index_path())
    end
  end

  # Private

  defp save(schedule, params) do
    holidays = holiday_params(params["holidays"])

    changeset =
      BusinessSchedule.changeset(schedule, %{
        name: params["name"],
        timezone: params["timezone"],
        is_default: truthy?(params["is_default"]),
        hours: schedule_param(params["schedule"])
      })
      |> Ecto.Changeset.validate_required([:hours], message: "can't be blank")

    errors =
      FormResponse.errors(changeset)
      |> Map.merge(holiday_errors(holidays))

    if errors == %{} do
      repo().transaction(fn -> persist(changeset, holidays) end)
    else
      {:error, errors}
    end
  end

  defp persist(changeset, holidays) do
    schedule =
      case repo().insert_or_update(changeset) do
        {:ok, schedule} -> schedule
        {:error, failed} -> repo().rollback(FormResponse.errors(failed))
      end

    if schedule.is_default do
      from(s in BusinessSchedule, where: s.is_default == true and s.id != ^schedule.id)
      |> repo().update_all(set: [is_default: false])
    end

    # The form sends the full list, so an update replaces it (as Laravel does).
    from(h in Holiday, where: h.business_schedule_id == ^schedule.id) |> repo().delete_all()

    for holiday <- holidays do
      %Holiday{}
      |> Holiday.changeset(Map.put(holiday, :business_schedule_id, schedule.id))
      |> repo().insert!()
    end

    schedule
  end

  # Only a map of weekdays is a schedule; each day keeps its start and end.
  defp schedule_param(%{} = schedule) do
    schedule
    |> Map.take(@days)
    |> Map.new(fn {day, value} -> {day, day_param(value)} end)
  end

  defp schedule_param(_), do: nil

  defp day_param(%{} = day),
    do: %{"start" => to_string(day["start"] || ""), "end" => to_string(day["end"] || "")}

  defp day_param(_), do: %{"start" => "", "end" => ""}

  # Inertia posts a JSON list; a form-encoded post arrives as an indexed map.
  defp holiday_params(list) when is_list(list), do: Enum.map(list, &holiday_param/1)

  defp holiday_params(%{} = indexed) do
    indexed
    |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
    |> Enum.map(fn {_, value} -> holiday_param(value) end)
  rescue
    ArgumentError -> [%{name: nil, date: :invalid, is_recurring: false}]
  end

  defp holiday_params(_), do: []

  defp holiday_param(%{} = h) do
    %{
      name: if(is_binary(h["name"]), do: String.trim(h["name"]), else: nil),
      date: parse_date(h["date"]),
      is_recurring: truthy?(h["recurring"])
    }
  end

  defp holiday_param(_), do: %{name: nil, date: :invalid, is_recurring: false}

  defp parse_date(value) when is_binary(value) do
    # The page may send back a date that came with a time ("2026-12-25T00:00:00Z").
    case Date.from_iso8601(value |> String.split("T") |> hd()) do
      {:ok, date} -> date
      _ -> :invalid
    end
  end

  defp parse_date(_), do: :invalid

  defp holiday_errors(holidays) do
    holidays
    |> Enum.with_index()
    |> Enum.flat_map(fn {h, i} ->
      name_error =
        cond do
          h.name in [nil, ""] ->
            [{"holidays.#{i}.name", ["can't be blank"]}]

          String.length(h.name) > 255 ->
            [{"holidays.#{i}.name", ["should be at most 255 character(s)"]}]

          true ->
            []
        end

      date_error =
        if h.date == :invalid, do: [{"holidays.#{i}.date", ["is not a valid date"]}], else: []

      name_error ++ date_error
    end)
    |> Map.new()
  end

  defp truthy?(value), do: value in [true, "true", "1", 1, "on"]

  defp schedule_json(%BusinessSchedule{} = s) do
    %{
      id: s.id,
      name: s.name,
      timezone: s.timezone,
      is_default: s.is_default,
      schedule: week_json(s.hours || %{}),
      holidays: Enum.map(s.holidays, &holiday_json/1),
      created_at: s.inserted_at && DateTime.to_iso8601(s.inserted_at),
      updated_at: s.updated_at && DateTime.to_iso8601(s.updated_at)
    }
  end

  # Every weekday, as the editor reads it: closed days have empty times. Rows
  # written with `"enabled" => false` read as closed.
  defp week_json(hours) do
    Map.new(@days, fn day ->
      value =
        case Map.get(hours, day) do
          %{"enabled" => false} -> %{"start" => "", "end" => ""}
          %{} = d -> %{"start" => d["start"] || "", "end" => d["end"] || ""}
          _ -> %{"start" => "", "end" => ""}
        end

      {day, value}
    end)
  end

  defp holiday_json(%Holiday{} = h) do
    %{
      id: h.id,
      schedule_id: h.business_schedule_id,
      name: h.name,
      date: Date.to_iso8601(h.date),
      recurring: h.is_recurring,
      created_at: h.inserted_at && DateTime.to_iso8601(h.inserted_at)
    }
  end

  defp find(id) do
    case Integer.parse(to_string(id)) do
      {int, ""} ->
        repo().one(from(s in BusinessSchedule, where: s.id == ^int, preload: [:holidays]))

      _ ->
        nil
    end
  end

  defp not_found(conn),
    do: conn |> put_status(404) |> json(%{error: "Business schedule not found"})

  defp repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())

  defp index_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/business-hours"
end
