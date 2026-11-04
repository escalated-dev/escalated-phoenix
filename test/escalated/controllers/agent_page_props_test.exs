defmodule Escalated.Controllers.AgentPagePropsTest do
  @moduledoc """
  The agent ticket pages are sent the props the shared frontend's components
  declare (test/fixtures/escalated-pages.json), so nothing the page reads is
  missing and nothing sent is dropped on the root element.
  """
  use Escalated.PageCase

  alias Escalated.Schemas.Ticket

  @manifest Path.join(__DIR__, "../../fixtures/escalated-pages.json")

  # Props every page is shared (Escalated.Plugs.ShareInertiaData and Inertia).
  @shared ~w(errors auth flash escalated ziggy page_name)

  # Sent on TicketShow beyond what the page declares: the ticket's custom field
  # values, which this package has sent there since custom fields shipped.
  @extra %{"Escalated/Agent/TicketShow" => ["custom_fields"]}

  for page <- ["Escalated/Agent/TicketIndex", "Escalated/Agent/TicketShow"] do
    test "sends #{page} every prop it declares" do
      agent = host_user!(%{name: "Al Agent", is_agent: true})

      ticket =
        Escalated.repo().insert!(%Ticket{
          subject: "Ticket",
          description: "Body",
          reference: "ESC-#{System.unique_integer([:positive])}"
        })

      path =
        if unquote(page) == "Escalated/Agent/TicketIndex",
          do: "/support/agent/tickets",
          else: "/support/agent/tickets/#{ticket.reference}"

      props = visit(:get, path, agent) |> page!(unquote(page))

      declared =
        @manifest
        |> File.read!()
        |> Jason.decode!()
        |> get_in(["props", unquote(page), "props"])

      sent = props |> Map.keys() |> Enum.reject(&(&1 in @shared)) |> Enum.sort()

      assert sent == Enum.sort(declared ++ Map.get(@extra, unquote(page), []))
    end
  end
end
