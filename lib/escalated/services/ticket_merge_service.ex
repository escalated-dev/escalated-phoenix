defmodule Escalated.Services.TicketMergeService do
  @moduledoc """
  Merges one ticket into another, as escalated-laravel's `TicketMergeService`.

  In one transaction, `merge/3`:

    * moves every reply and internal note of the source onto the target (with
      the attachments on those replies);
    * adds a system note to each ticket: "Ticket {source} was merged into this
      ticket." on the target and "This ticket was merged into {target}." on the
      source;
    * closes the source and records the target in its `merged_into_id`.

  After the commit the source's close is announced like any other status
  change (`TicketService.announce_status_change/3`), so webhooks, workflows and
  notification emails see `ticket.status_changed` and `ticket.closed`.

  A ticket cannot be merged into itself, a merged ticket cannot be merged
  again, and nothing can be merged into a merged ticket.
  """

  import Ecto.Query

  alias Escalated.Schemas.{Attachment, Reply, Ticket}
  alias Escalated.Services.TicketService

  @doc """
  Merge `source` into `target`. `opts[:actor_id]` is the user doing it.

  Returns `{:ok, %{source: closed_source, target: target}}` or
  `{:error, :same_ticket | :already_merged | :target_merged | term}`.
  """
  def merge(%Ticket{} = source, %Ticket{} = target, opts \\ []) do
    Escalated.TicketVisibility.assert_record!(source)
    Escalated.TicketVisibility.assert_record!(target)

    cond do
      source.id == target.id -> {:error, :same_ticket}
      not is_nil(source.merged_into_id) -> {:error, :already_merged}
      not is_nil(target.merged_into_id) -> {:error, :target_merged}
      true -> do_merge(source, target, Keyword.get(opts, :actor_id))
    end
  end

  defp do_merge(source, target, actor_id) do
    repo = Escalated.repo()

    repo.transaction(fn ->
      with :ok <- move_replies(repo, source, target),
           {:ok, _} <-
             system_note(repo, target, "Ticket #{source.reference} was merged into this ticket."),
           {:ok, _} <-
             system_note(repo, source, "This ticket was merged into #{target.reference}."),
           {:ok, closed} <- close_into(repo, source, target) do
        closed
      else
        {:error, reason} -> repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, closed} ->
        TicketService.announce_status_change(source, closed, actor_id: actor_id)
        {:ok, %{source: closed, target: target}}

      error ->
        error
    end
  end

  # Row by row rather than update_all: under tenancy and ticket visibility a
  # bulk change of ticket_id is refused, while update/2 checks each row's new
  # parent.
  defp move_replies(repo, source, target) do
    replies = repo.all(from(r in Reply, where: r.ticket_id == ^source.id, order_by: r.id))
    reply_ids = Enum.map(replies, & &1.id)

    attachments =
      if reply_ids == [],
        do: [],
        else: repo.all(from(a in Attachment, where: a.reply_id in ^reply_ids))

    moves =
      Enum.map(replies, &Ecto.Changeset.change(&1, ticket_id: target.id)) ++
        Enum.map(attachments, &Ecto.Changeset.change(&1, ticket_id: target.id))

    Enum.reduce_while(moves, :ok, fn changeset, :ok ->
      case repo.update(changeset) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp system_note(repo, ticket, body) do
    %Reply{}
    |> Reply.changeset(%{
      ticket_id: ticket.id,
      body: body,
      is_internal: true,
      is_system: true,
      author_id: nil
    })
    |> repo.insert()
  end

  defp close_into(repo, source, target) do
    source
    |> Ticket.changeset(%{status: "closed", closed_at: DateTime.utc_now()})
    |> Ecto.Changeset.put_change(:merged_into_id, target.id)
    |> repo.update()
  end
end
