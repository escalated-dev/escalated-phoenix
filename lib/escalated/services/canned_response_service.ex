defmodule Escalated.Services.CannedResponseService do
  @moduledoc """
  Reusable agent reply templates ("canned responses").

  Each canned response is either shared (visible to every agent) or private
  to its creator. Admins manage the full library via the admin controller;
  agents fetch the subset visible to them (`list_for_agent/2`) via the agent
  controller. Mirrors the laravel/rails/django ports.

  Acts as the context module for canned responses (CRUD + list), following
  the `MacroService` / `AutomationRunner` convention in this package.
  """

  import Ecto.Query

  alias Escalated.Schemas.CannedResponse

  @doc "All canned responses, title-ordered (admin library view)."
  @spec list(module()) :: [CannedResponse.t()]
  def list(repo) when is_atom(repo) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    CannedResponse
    |> order_by([c], asc: c.title)
    |> repo.all()
  end

  @doc "Canned responses visible to an agent: shared plus their own."
  @spec list_for_agent(module(), integer() | binary()) :: [CannedResponse.t()]
  def list_for_agent(repo, agent_id) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    CannedResponse
    |> CannedResponse.for_agent(agent_id)
    |> repo.all()
  end

  @doc "Only shared canned responses, title-ordered."
  @spec list_shared(module()) :: [CannedResponse.t()]
  def list_shared(repo) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    CannedResponse
    |> CannedResponse.shared()
    |> repo.all()
  end

  @spec find_by_id(module(), integer() | binary()) :: CannedResponse.t() | nil
  def find_by_id(repo, id) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    repo.get(CannedResponse, id)
  end

  @spec create(module(), map()) :: {:ok, CannedResponse.t()} | {:error, Ecto.Changeset.t()}
  def create(repo, attrs) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    %CannedResponse{}
    |> CannedResponse.changeset(attrs)
    |> repo.insert()
  end

  @spec update(module(), CannedResponse.t(), map()) ::
          {:ok, CannedResponse.t()} | {:error, Ecto.Changeset.t()}
  def update(repo, %CannedResponse{} = canned_response, attrs) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    canned_response
    |> CannedResponse.changeset(attrs)
    |> repo.update()
  end

  @spec delete(module(), CannedResponse.t()) ::
          {:ok, CannedResponse.t()} | {:error, Ecto.Changeset.t()}
  def delete(repo, %CannedResponse{} = canned_response) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    repo.delete(canned_response)
  end
end
