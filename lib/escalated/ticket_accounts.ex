defmodule Escalated.TicketAccounts do
  @moduledoc "Host account resolution for ticket requesters and subjects."
  import Ecto.Query
  alias Ecto.Changeset
  alias Escalated.Schemas.Ticket
  alias Escalated.TicketVisibility

  def resolve(changeset, source \\ nil) do
    pair =
      if source do
        TicketVisibility.pair(%{type: source.account_type, id: source.account_id})
      else
        TicketVisibility.resolve_account(
          :requester,
          Changeset.get_field(changeset, :requester_type),
          Changeset.get_field(changeset, :requester_id)
        )
      end

    case pair do
      %{type: type, id: id} ->
        changeset
        |> Changeset.put_change(:account_type, type)
        |> Changeset.put_change(:account_id, id)

      _ ->
        changeset
    end
  end

  def attach(ticket, type, id) do
    TicketVisibility.assert_record!(ticket)

    case TicketVisibility.resolve_account(:subject, type, id) do
      %{type: account_type, id: account_id} ->
        # Compare-and-set keeps the first complete account, including concurrent subjects.
        query =
          from(t in Ticket,
            where: t.id == ^ticket.id and is_nil(t.account_type) and is_nil(t.account_id)
          )

        Escalated.repo().update_all(query,
          set: [account_type: account_type, account_id: account_id]
        )

      _ ->
        :ok
    end
  end
end
