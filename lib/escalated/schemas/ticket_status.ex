defmodule Escalated.Schemas.TicketStatus do
  @moduledoc """
  A ticket status an admin defines: a sub-status of one of five categories
  (`new`, `open`, `pending`, `on_hold`, `solved`).

  All lifecycle logic keys off the category. Giving a ticket a custom status
  sets its built-in `status` to the category's anchor (`anchor/1`) and
  records the custom one in `ticket_status_id`; see
  `Escalated.Services.TicketService.transition_status/3`.

  System rows (`is_system`) stand for the built-in statuses: their slug is the
  built-in value and their slug and category never change.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @categories ~w(new open pending on_hold solved)

  @anchors %{
    "new" => "open",
    "open" => "open",
    "pending" => "waiting_on_customer",
    "on_hold" => "in_progress",
    "solved" => "resolved"
  }

  # The built-in statuses: slug => {label, colour, category}. Labels and
  # colours are the ones Escalated.Controllers.GuestTicketView shows.
  @system [
    {"open", "Open", "#3B82F6", "open"},
    {"in_progress", "In Progress", "#8B5CF6", "open"},
    {"waiting_on_customer", "Waiting on Customer", "#F59E0B", "pending"},
    {"waiting_on_agent", "Waiting on Agent", "#F97316", "open"},
    {"escalated", "Escalated", "#EF4444", "open"},
    {"resolved", "Resolved", "#10B981", "solved"},
    {"closed", "Closed", "#6B7280", "solved"},
    {"reopened", "Reopened", "#3B82F6", "open"},
    {"snoozed", "Snoozed", "#6B7280", "on_hold"},
    {"live", "Live", "#06B6D4", "open"}
  ]

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}ticket_statuses" do
    field :tenant_id, :string, default: ""
    field :label, :string
    field :slug, :string
    field :category, :string
    field :color, :string, default: "#6b7280"
    field :description, :string
    field :position, :integer, default: 0
    field :is_default, :boolean, default: false
    field :is_system, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc "The five categories, in Laravel's order."
  def categories, do: @categories

  @doc "The built-in status a ticket takes for a custom status of `category`."
  def anchor(category), do: Map.fetch!(@anchors, category)

  @doc "The built-in statuses as `{slug, label, colour, category}`."
  def system_statuses, do: @system

  @doc "The category of a built-in status."
  def builtin_category("waiting_on_customer"), do: "pending"
  def builtin_category("snoozed"), do: "on_hold"
  def builtin_category(status) when status in ["resolved", "closed"], do: "solved"
  def builtin_category(_status), do: "open"

  @doc false
  def changeset(status, attrs) do
    status
    |> cast(attrs, [:label, :slug, :category, :color, :description, :position, :is_default])
    |> validate_required([:label, :slug, :category, :color])
    |> validate_length(:label, max: 255)
    |> validate_length(:color, max: 20)
    |> validate_inclusion(:category, @categories)
    |> unique_constraint(:slug)
    |> Escalated.Tenancy.Constraints.add_unique_constraints()
    |> keep_system_identity()
  end

  @doc "Builds a system row for a built-in status."
  def system_changeset({slug, label, color, category}, position) do
    %__MODULE__{}
    |> change(%{
      slug: slug,
      label: label,
      color: color,
      category: category,
      position: position,
      is_system: true
    })
    |> unique_constraint(:slug)
    |> Escalated.Tenancy.Constraints.add_unique_constraints()
  end

  # A system row's slug and category are the built-in status's.
  defp keep_system_identity(%Ecto.Changeset{data: %{is_system: true}} = changeset) do
    changeset
    |> validate_change(:slug, fn :slug, _ -> [slug: "cannot be changed on a system status"] end)
    |> validate_change(:category, fn :category, _ ->
      [category: "cannot be changed on a system status"]
    end)
  end

  defp keep_system_identity(changeset), do: changeset
end
