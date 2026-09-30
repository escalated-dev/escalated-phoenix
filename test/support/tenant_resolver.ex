defmodule Escalated.Test.TenantResolver do
  @moduledoc false
  import Ecto.Query

  def resolve(conn), do: conn.assigns[:trusted_tenant]
  def member?(%{id: id}, tenant), do: reference?(:user, id, tenant)
  def member?(_, _), do: false

  def reference?(:user, id, tenant) do
    Escalated.HostTestRepo.exists?(
      from(u in Escalated.Test.HostUser, where: u.id == ^id and u.name == ^tenant)
    )
  end

  def reference?("shipment", id, tenant), do: id == "#{tenant}-parcel"
  def reference?(_, _, _), do: false

  def scope_users(query, tenant), do: where(query, [u], u.name == ^tenant)
end
