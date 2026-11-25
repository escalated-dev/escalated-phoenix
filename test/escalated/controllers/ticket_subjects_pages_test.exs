defmodule Escalated.Controllers.TicketSubjectsPagesTest do
  @moduledoc """
  The agent and admin ticket pages send `ticket.subjects` (the host records a
  ticket is linked to, which the sidebar's Related card shows), serialised
  exactly as the API ticket resource serialises them.
  """
  use Escalated.PageCase

  alias Escalated.Serializers.TicketSerializer
  alias Escalated.Services.{TicketService, TicketSubjectService}

  setup do
    previous = Application.fetch_env(:escalated, :ticket_subjects)

    Application.put_env(:escalated, :ticket_subjects,
      resolver: fn "project", "7" ->
        %Escalated.Test.FakeProject{id: "7", name: "Acme Redesign", account: "Acme"}
      end
    )

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:escalated, :ticket_subjects, value)
        :error -> Application.delete_env(:escalated, :ticket_subjects)
      end
    end)

    {:ok, ticket} = TicketService.create(%{subject: "Refund please", description: "Twice"})

    %{
      ticket: ticket,
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      agent: host_user!(%{name: "Al Agent", is_agent: true})
    }
  end

  test "both show pages send ticket.subjects as the API ticket resource does", ctx do
    {:ok, _link} = TicketSubjectService.attach_subject(ctx.ticket, "project", "7")

    api = ctx.ticket |> TicketSerializer.subjects() |> Jason.encode!() |> Jason.decode!()
    assert [%{"type" => "project", "id" => "7", "title" => "Acme Redesign"}] = api

    for {path, component, user} <- [
          {"/support/agent/tickets/#{ctx.ticket.reference}", "Escalated/Agent/TicketShow",
           ctx.agent},
          {"/support/admin/tickets/#{ctx.ticket.reference}", "Escalated/Admin/Tickets/Show",
           ctx.admin}
        ] do
      props = visit(:get, path, user) |> page!(component)
      assert props["ticket"]["subjects"] == api, component
    end
  end
end
