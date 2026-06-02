defmodule Escalated.Test.FakeProject do
  @moduledoc false
  @behaviour Escalated.TicketSubject

  defstruct [:id, :name, :account]

  @impl Escalated.TicketSubject
  def ticket_subject_title(%__MODULE__{name: name}), do: name

  @impl Escalated.TicketSubject
  def ticket_subject_subtitle(%__MODULE__{account: account}),
    do: "Project · #{account}"

  @impl Escalated.TicketSubject
  def ticket_subject_url(%__MODULE__{id: id}), do: "https://app.test/projects/#{id}"

  @impl Escalated.TicketSubject
  def ticket_subject_color(_), do: "#2563eb"

  @impl Escalated.TicketSubject
  def ticket_subject_icon(_), do: "folder"
end
