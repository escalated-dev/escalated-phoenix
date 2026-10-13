defmodule Escalated.Schemas.DepartmentAgent do
  @moduledoc "Package-owned department memberships; agent ids belong to the host's user store."
  use Ecto.Schema
  import Ecto.Changeset
  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}department_agent" do
    field :tenant_id, :string, default: ""
    field :agent_id, @user_id_type
    belongs_to :department, Escalated.Schemas.Department
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:agent_id, :department_id])
    |> validate_required([:agent_id, :department_id])
  end
end
