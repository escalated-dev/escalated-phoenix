defmodule Escalated.WidgetDepartments do
  @moduledoc """
  The departments the support widget offers, and the department a widget
  ticket or chat is filed under.

  The widget lists the active departments and sends the chosen one as
  `department_id`. A value that names no active department (an inactive or
  deleted one, or something that is not an id) is ignored, so the ticket is
  filed without a department instead of failing.
  """
  import Ecto.Query
  alias Escalated.Schemas.Department

  @doc "Active departments as `[%{id, name}]`, ordered by name."
  def list do
    Department.active()
    |> Department.ordered()
    |> select([d], %{id: d.id, name: d.name})
    |> Escalated.repo().all()
  end

  @doc "The id of the active department `value` names, or nil."
  def resolve(value) do
    case id(value) do
      nil ->
        nil

      id ->
        Department.active()
        |> where([d], d.id == ^id)
        |> select([d], d.id)
        |> Escalated.repo().one()
    end
  end

  # Ids are bigints; anything larger could not be one, and PostgreSQL would
  # refuse to compare it.
  @max_id 9_223_372_036_854_775_807

  defp id(value) when is_integer(value) and value > 0 and value <= @max_id, do: value

  defp id(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {id, ""} when id > 0 and id <= @max_id -> id
      _ -> nil
    end
  end

  defp id(_), do: nil
end
