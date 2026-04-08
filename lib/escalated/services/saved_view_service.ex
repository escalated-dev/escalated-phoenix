defmodule Escalated.Services.SavedViewService do
  @moduledoc """
  Context module for CRUD operations on saved views (custom queues).
  """

  alias Escalated.Schemas.SavedView
  import Ecto.Query

  @doc """
  Creates a new saved view.
  """
  def create(attrs) do
    repo = Escalated.repo()

    %SavedView{}
    |> SavedView.changeset(attrs)
    |> repo.insert()
  end

  @doc """
  Updates an existing saved view.

  Only the owner can update. Returns `{:error, :unauthorized}` if the
  actor does not own the view.
  """
  def update(view, attrs, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)

    if actor_id && view.user_id != actor_id do
      {:error, :unauthorized}
    else
      view
      |> SavedView.changeset(attrs)
      |> repo.update()
    end
  end

  @doc """
  Deletes a saved view.

  Only the owner can delete. Returns `{:error, :unauthorized}` if the
  actor does not own the view.
  """
  def delete(view, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)

    if actor_id && view.user_id != actor_id do
      {:error, :unauthorized}
    else
      repo.delete(view)
    end
  end

  @doc """
  Lists all views accessible by a user (own views + shared views),
  ordered by position.
  """
  def list_for_user(user_id) do
    repo = Escalated.repo()

    SavedView
    |> SavedView.accessible_by(user_id)
    |> SavedView.ordered()
    |> repo.all()
  end

  @doc """
  Finds a saved view by ID.
  """
  def find(id) do
    Escalated.repo().get(SavedView, id)
  end

  @doc """
  Reorders views for a user by accepting a list of `{id, position}` tuples.
  """
  def reorder(view_positions) do
    repo = Escalated.repo()

    results =
      Enum.map(view_positions, fn {id, position} ->
        case repo.get(SavedView, id) do
          nil ->
            {:error, :not_found}

          view ->
            view
            |> SavedView.changeset(%{position: position})
            |> repo.update()
        end
      end)

    {:ok, results}
  end
end
