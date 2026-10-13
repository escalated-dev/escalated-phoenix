defmodule Escalated.Services.TicketRoutingConditions do
  @moduledoc false
  alias Escalated.TicketVisibility
  @fields ~w(account account_type account_id ticket_type)
  def routing?(%{"field" => field}), do: field in @fields
  def routing?(_), do: false

  def matches_all?(conditions, ticket),
    do: Enum.all?(Enum.filter(conditions || [], &routing?/1), &matches?(&1, ticket))

  def matches?(%{"field" => "account", "value" => value} = condition, ticket) do
    expected = TicketVisibility.pair(value)

    actual =
      TicketVisibility.pair(%{
        type: field(ticket, "account_type"),
        id: field(ticket, "account_id")
      })

    not is_nil(expected) and compare(condition["operator"] || "equals", actual, expected)
  end

  def matches?(%{"field" => field, "value" => expected} = condition, ticket)
      when field in @fields do
    actual = field(ticket, field)

    is_binary(expected) and expected != "" and
      compare(condition["operator"] || "equals", actual, expected)
  end

  def matches?(_, _), do: false
  defp field(ticket, key), do: Map.get(ticket, key, Map.get(ticket, String.to_existing_atom(key)))
  defp compare(op, actual, expected) when op in ["equals", "=", "=="], do: actual == expected
  defp compare(op, actual, expected) when op in ["not_equals", "!="], do: actual != expected
  defp compare(_, _, _), do: false
end
