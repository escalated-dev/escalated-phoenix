defmodule Escalated.Controllers.Admin.SlaPolicyController do
  @moduledoc """
  Admin CRUD over SLA policies, serving `Escalated/Admin/SlaPolicies/Index`
  and `Escalated/Admin/SlaPolicies/Form` with the props escalated-laravel's
  `SlaPolicyController` sends.

  Business hours are global here (`sla: %{business_hours_only: ...}` in the
  package configuration), not per policy, so `business_hours_only` is reported from that
  setting and a value posted with a policy is not stored.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{Department, SlaPolicy, Ticket}

  @fields ~w(name description is_default is_active first_response_hours resolution_hours department_id ticket_type)

  def index(conn, _params) do
    repo = repo()

    counts =
      from(t in Ticket,
        where: not is_nil(t.sla_policy_id),
        group_by: t.sla_policy_id,
        select: {t.sla_policy_id, count(t.id)}
      )
      |> Escalated.repo().all()
      |> Map.new()

    policies =
      from(p in SlaPolicy, order_by: [asc: p.name])
      |> repo.all()
      |> Enum.map(&Map.put(policy_json(&1), :tickets_count, Map.get(counts, &1.id, 0)))

    UIRenderer.render_page(conn, "Escalated/Admin/SlaPolicies/Index", %{policies: policies})
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/SlaPolicies/Form", form_options())
  end

  def edit(conn, %{"id" => id}) do
    case repo().get(SlaPolicy, id) do
      nil ->
        not_found(conn)

      policy ->
        UIRenderer.render_page(
          conn,
          "Escalated/Admin/SlaPolicies/Form",
          Map.put(form_options(), :policy, policy_json(policy))
        )
    end
  end

  def create(conn, params) do
    %SlaPolicy{}
    |> SlaPolicy.changeset(Map.take(params, @fields))
    |> repo().insert()
    |> case do
      {:ok, _} ->
        conn |> put_flash(:info, "SLA policy created.") |> redirect(to: index_path())

      {:error, changeset} ->
        FormResponse.invalid(conn, changeset, index_path() <> "/create")
    end
  end

  def update(conn, %{"id" => id} = params) do
    case repo().get(SlaPolicy, id) do
      nil ->
        not_found(conn)

      policy ->
        policy
        |> SlaPolicy.changeset(Map.take(params, @fields))
        |> repo().update()
        |> case do
          {:ok, _} ->
            conn |> put_flash(:info, "SLA policy updated.") |> redirect(to: index_path())

          {:error, changeset} ->
            FormResponse.invalid(conn, changeset, "#{index_path()}/#{id}/edit")
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case repo().get(SlaPolicy, id) do
      nil ->
        not_found(conn)

      policy ->
        # Tickets keep their due dates; they only lose the link to the policy.
        from(t in Ticket, where: t.sla_policy_id == ^policy.id)
        |> Escalated.repo().update_all(set: [sla_policy_id: nil])

        repo().delete!(policy)
        conn |> put_flash(:info, "SLA policy deleted.") |> redirect(to: index_path())
    end
  end

  defp policy_json(p) do
    %{
      id: p.id,
      name: p.name,
      description: p.description,
      is_default: p.is_default,
      is_active: p.is_active,
      first_response_hours: p.first_response_hours || %{},
      resolution_hours: p.resolution_hours || %{},
      business_hours_only: business_hours_only?(),
      department_id: p.department_id,
      ticket_type: p.ticket_type,
      created_at: p.inserted_at && DateTime.to_iso8601(p.inserted_at),
      updated_at: p.updated_at && DateTime.to_iso8601(p.updated_at)
    }
  end

  defp form_options do
    %{
      priorities: Ticket.priorities(),
      targeted: Escalated.configuration().targeted_slas == true,
      departments:
        repo().all(Department.active() |> Department.ordered())
        |> Enum.map(&%{id: &1.id, name: &1.name}),
      ticketTypes: Ticket.ticket_types()
    }
  end

  defp business_hours_only? do
    !!Escalated.configuration().sla[:business_hours_only]
  end

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "SLA policy not found"})

  defp repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())

  defp index_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/sla-policies"
end
