defmodule Escalated.Controllers.Api.GuestTicketControllerTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.TicketService

  defp repo, do: Escalated.repo()

  test "the guest ticket controller is compiled" do
    assert Code.ensure_loaded?(Escalated.Controllers.Api.GuestTicketController)
  end

  test "a guest ticket is created (resolving a contact) and fetched by token" do
    token = "guesttoken123abc"

    {:ok, ticket} =
      TicketService.create(%{
        subject: "Help",
        description: "Please assist",
        guest_name: "Pat",
        guest_email: "pat@example.com",
        guest_token: token,
        priority: "medium"
      })

    assert ticket.guest_token == token

    found = repo().get_by(Ticket, guest_token: token)
    assert found.id == ticket.id
    assert found.guest_email == "pat@example.com"
  end
end
