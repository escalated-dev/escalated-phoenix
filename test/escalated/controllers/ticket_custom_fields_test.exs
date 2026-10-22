defmodule Escalated.Controllers.TicketCustomFieldsTest do
  @moduledoc """
  Ticket custom field values (`custom_fields`, keyed by field slug) through the
  real router: the customer create page and its write, the agent update, the
  JSON API create and detail, and the staff and customer show pages.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{CustomField, CustomFieldValue, Ticket}
  alias Escalated.Services.TicketService

  @definition_keys ~w(id name slug type options required placeholder description position)

  defp repo, do: Escalated.repo()

  setup do
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
    on_exit(fn -> Application.delete_env(:escalated, :agent_check) end)

    %{
      agent: host_user!(%{name: "Al Agent", is_agent: true}),
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      customer: host_user!(%{name: "Cy Customer"})
    }
  end

  defp field!(slug, type, attrs \\ %{}) do
    %CustomField{}
    |> CustomField.changeset(
      Map.merge(%{name: String.capitalize(slug), slug: slug, field_type: type}, attrs)
    )
    |> repo().insert!()
  end

  defp standard_fields! do
    %{
      order: field!("order_number", "text", %{is_required: true, position: 1}),
      notes: field!("notes", "textarea", %{position: 2}),
      seats: field!("seats", "number", %{position: 3}),
      due: field!("due_on", "date", %{position: 4}),
      vip: field!("vip", "checkbox", %{position: 5}),
      plan: field!("plan", "select", %{options: ["Free", "Pro"], position: 6}),
      os: field!("platforms", "multi_select", %{options: ["mac", "win", "linux"], position: 7})
    }
  end

  defp ticket!(customer) do
    {:ok, ticket} =
      TicketService.create(%{
        subject: "Help",
        description: "Details",
        requester_id: customer.id,
        requester_type: "user"
      })

    ticket
  end

  defp stored(ticket) do
    repo().all(
      from(v in CustomFieldValue,
        join: f in CustomField,
        on: f.id == v.custom_field_id,
        where: v.entity_type == "ticket" and v.entity_id == ^ticket.id,
        select: {f.slug, v.value}
      )
    )
    |> Map.new()
  end

  defp customer_create(customer, custom_fields) do
    body = %{"subject" => "Broken", "description" => "It broke"}

    body =
      if custom_fields == :omit, do: body, else: Map.put(body, "custom_fields", custom_fields)

    visit(:post, "/support/tickets", customer, body)
  end

  defp api_create(user, ticket) do
    conn(:post, "/support/api/v1/tickets", Jason.encode!(%{"ticket" => ticket}))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
  end

  defp api_get(user, path) do
    conn(:get, path)
    |> put_req_header("accept", "application/json")
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
  end

  defp agent_update(agent, ticket, body, inertia? \\ false) do
    if inertia? do
      visit(:put, "/support/agent/tickets/#{ticket.reference}", agent, body)
    else
      conn(:put, "/support/agent/tickets/#{ticket.reference}", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> init_test_session(%{})
      |> assign(:current_user, agent)
      |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
    end
  end

  defp create_errors(conn) do
    props = page!(conn, "Escalated/Customer/Create")
    props["errors"]
  end

  describe "Customer/Create" do
    test "sends the active ticket definitions ordered by position", %{customer: customer} do
      field!("second", "text", %{position: 2})
      field!("first", "select", %{position: 1, options: ["a", "b"], placeholder: "Pick"})
      field!("hidden", "text", %{position: 0, is_active: false})
      field!("company_size", "number", %{position: 0, entity_type: "organization"})

      props = visit(:get, "/support/tickets/new", customer) |> page!("Escalated/Customer/Create")

      assert [first, second] = props["custom_fields"]
      assert_keys(first, @definition_keys, "custom field")
      assert first["slug"] == "first"
      assert first["type"] == "select"
      assert first["options"] == ["a", "b"]
      assert first["placeholder"] == "Pick"
      assert first["required"] == false
      assert second["slug"] == "second"
    end

    test "is an empty list with no fields defined", %{customer: customer} do
      props = visit(:get, "/support/tickets/new", customer) |> page!("Escalated/Customer/Create")
      assert props["custom_fields"] == []
    end
  end

  describe "customer create" do
    test "stores every type with the shared encoding", %{customer: customer} do
      standard_fields!()

      conn =
        customer_create(customer, %{
          "order_number" => "ORD-1",
          "notes" => "Long text",
          "seats" => 12,
          "due_on" => "2026-11-30",
          "vip" => true,
          "plan" => "Pro",
          "platforms" => ["mac", "linux"]
        })

      assert conn.status in [302, 303]
      ticket = repo().one!(Ticket)

      assert stored(ticket) == %{
               "order_number" => "ORD-1",
               "notes" => "Long text",
               "seats" => "12",
               "due_on" => "2026-11-30",
               "vip" => "1",
               "plan" => "Pro",
               "platforms" => ~s(["mac","linux"])
             }
    end

    test "a missing required field creates no ticket", %{customer: customer} do
      standard_fields!()

      errors = customer_create(customer, %{"notes" => "x"}) |> create_errors()
      assert Map.has_key?(errors, "custom_fields.order_number")

      errors = customer_create(customer, :omit) |> create_errors()
      assert Map.has_key?(errors, "custom_fields.order_number")

      errors = customer_create(customer, %{"order_number" => "  "}) |> create_errors()
      assert Map.has_key?(errors, "custom_fields.order_number")

      assert repo().aggregate(Ticket, :count) == 0
      assert repo().aggregate(CustomFieldValue, :count) == 0
    end

    test "each type is checked", %{customer: customer} do
      standard_fields!()

      bad = %{
        "order_number" => String.duplicate("x", 256),
        "notes" => 42,
        "seats" => "twelve",
        "due_on" => "2026-02-30",
        "vip" => "maybe",
        "plan" => "Enterprise",
        "platforms" => ["mac", "beos"]
      }

      errors = customer_create(customer, bad) |> create_errors()

      for slug <- Map.keys(bad) do
        assert Map.has_key?(errors, "custom_fields.#{slug}"), "no error for #{slug}"
      end

      errors =
        customer_create(customer, %{
          "order_number" => "ok",
          "due_on" => "30/11/2026",
          "platforms" => "mac"
        })
        |> create_errors()

      assert Map.has_key?(errors, "custom_fields.due_on")
      assert Map.has_key?(errors, "custom_fields.platforms")
      assert repo().aggregate(Ticket, :count) == 0
    end

    test "checkbox accepts the boolean spellings", %{customer: customer} do
      field!("vip", "checkbox")

      for {sent, expected} <- [
            {true, "1"},
            {false, "0"},
            {1, "1"},
            {0, "0"},
            {"1", "1"},
            {"0", "0"},
            {"true", "1"},
            {"false", "0"}
          ] do
        conn = customer_create(customer, %{"vip" => sent})
        assert conn.status in [302, 303], "#{inspect(sent)} was refused"
        ticket = repo().one!(from(t in Ticket, order_by: [desc: t.id], limit: 1))
        assert stored(ticket) == %{"vip" => expected}
      end
    end

    test "unknown, inactive and non-ticket keys are refused", %{customer: customer} do
      field!("old", "text", %{is_active: false})
      field!("company_size", "number", %{entity_type: "organization"})

      for key <- ~w(nope old company_size) do
        errors = customer_create(customer, %{key => "1"}) |> create_errors()
        assert Map.has_key?(errors, "custom_fields.#{key}"), "#{key} was accepted"
      end

      assert repo().aggregate(Ticket, :count) == 0
    end

    test "an inactive required field is not required", %{customer: customer} do
      field!("old", "text", %{is_active: false, is_required: true})

      assert customer_create(customer, :omit).status in [302, 303]
      assert repo().aggregate(Ticket, :count) == 1
    end

    test "with no fields defined the request behaves as before", %{customer: customer} do
      assert customer_create(customer, :omit).status in [302, 303]
      assert repo().aggregate(Ticket, :count) == 1
      assert repo().aggregate(CustomFieldValue, :count) == 0
    end

    test "numeric field ids are accepted as keys", %{customer: customer} do
      field = field!("order_number", "text")

      assert customer_create(customer, %{to_string(field.id) => "ORD-9"}).status in [302, 303]
      assert stored(repo().one!(Ticket)) == %{"order_number" => "ORD-9"}
    end
  end

  describe "agent update" do
    setup %{customer: customer} do
      fields = standard_fields!()
      ticket = ticket!(customer)

      TicketService.save_custom_fields(ticket, %{
        "order_number" => "ORD-1",
        "notes" => "keep me",
        "plan" => "Free"
      })

      %{fields: fields, ticket: ticket}
    end

    test "updates only the keys sent", %{agent: agent, ticket: ticket} do
      conn =
        agent_update(agent, ticket, %{
          "subject" => "New subject",
          "custom_fields" => %{"plan" => "Pro", "seats" => "3.5"}
        })

      assert conn.status in [302, 303]
      assert repo().get!(Ticket, ticket.id).subject == "New subject"

      assert stored(ticket) == %{
               "order_number" => "ORD-1",
               "notes" => "keep me",
               "plan" => "Pro",
               "seats" => "3.5"
             }
    end

    test "omitting custom_fields changes nothing", %{agent: agent, ticket: ticket} do
      before = stored(ticket)
      assert agent_update(agent, ticket, %{"subject" => "Only subject"}).status in [302, 303]
      assert stored(ticket) == before
    end

    test "an empty optional value clears it", %{agent: agent, ticket: ticket} do
      conn = agent_update(agent, ticket, %{"custom_fields" => %{"notes" => "", "plan" => nil}})

      assert conn.status in [302, 303]
      assert stored(ticket) == %{"order_number" => "ORD-1"}
    end

    test "a sent required field cannot be blank, and nothing is written", %{
      agent: agent,
      ticket: ticket
    } do
      conn =
        agent_update(agent, ticket, %{
          "subject" => "Changed",
          "custom_fields" => %{"order_number" => "", "plan" => "Pro"}
        })

      assert conn.status == 422
      assert Map.has_key?(Jason.decode!(conn.resp_body)["errors"], "custom_fields.order_number")
      assert repo().get!(Ticket, ticket.id).subject == "Help"
      assert stored(ticket)["plan"] == "Free"
    end

    test "an Inertia update gets its errors back on the session", %{agent: agent, ticket: ticket} do
      conn = agent_update(agent, ticket, %{"custom_fields" => %{"seats" => "x"}}, true)

      assert conn.status in [302, 303]
      errors = get_session(conn, "inertia_errors")
      assert Map.has_key?(errors, "custom_fields.seats")
    end

    test "customers cannot use it", %{customer: customer, ticket: ticket} do
      conn = agent_update(customer, ticket, %{"custom_fields" => %{"plan" => "Pro"}})
      assert conn.status == 403
      assert stored(ticket)["plan"] == "Free"
    end
  end

  describe "show pages" do
    setup %{customer: customer} do
      fields = standard_fields!()
      ticket = ticket!(customer)

      TicketService.save_custom_fields(ticket, %{
        "order_number" => "ORD-1",
        "seats" => "4",
        "vip" => "false",
        "platforms" => ["win"]
      })

      %{fields: fields, ticket: ticket}
    end

    defp assert_values(custom_fields) do
      assert length(custom_fields) == 7
      Enum.each(custom_fields, &assert_keys(&1, @definition_keys ++ ["value"], "custom field"))
      values = Map.new(custom_fields, &{&1["slug"], &1["value"]})

      assert values == %{
               "order_number" => "ORD-1",
               "notes" => nil,
               "seats" => 4,
               "due_on" => nil,
               "vip" => false,
               "plan" => nil,
               "platforms" => ["win"]
             }

      assert Enum.map(custom_fields, & &1["slug"]) ==
               ~w(order_number notes seats due_on vip plan platforms)
    end

    test "Agent/TicketShow", %{agent: agent, ticket: ticket} do
      visit(:get, "/support/agent/tickets/#{ticket.reference}", agent)
      |> page!("Escalated/Agent/TicketShow")
      |> Map.fetch!("custom_fields")
      |> assert_values()
    end

    test "Admin/Tickets/Show", %{admin: admin, ticket: ticket} do
      visit(:get, "/support/admin/tickets/#{ticket.reference}", admin)
      |> page!("Escalated/Admin/Tickets/Show")
      |> Map.fetch!("custom_fields")
      |> assert_values()
    end

    test "Customer/Show", %{customer: customer, ticket: ticket} do
      visit(:get, "/support/tickets/#{ticket.reference}", customer)
      |> page!("Escalated/Customer/Show")
      |> Map.fetch!("custom_fields")
      |> assert_values()
    end

    test "API detail", %{agent: agent, ticket: ticket} do
      conn = api_get(agent, "/support/api/v1/tickets/#{ticket.reference}")
      assert conn.status == 200
      Jason.decode!(conn.resp_body)["data"]["custom_fields"] |> assert_values()
    end
  end

  describe "API create" do
    test "stores the values and returns them", %{agent: agent, customer: customer} do
      field!("order_number", "text", %{is_required: true})

      conn =
        api_create(agent, %{
          "subject" => "API",
          "description" => "From the API",
          "requester_id" => customer.id,
          "requester_type" => "user",
          "custom_fields" => %{"order_number" => "ORD-7"}
        })

      assert conn.status == 201
      [field] = Jason.decode!(conn.resp_body)["data"]["custom_fields"]
      assert field["value"] == "ORD-7"
    end

    test "a 422 keyed by slug and no ticket", %{agent: agent, customer: customer} do
      field!("order_number", "text", %{is_required: true})

      conn =
        api_create(agent, %{
          "subject" => "API",
          "description" => "From the API",
          "requester_id" => customer.id,
          "requester_type" => "user"
        })

      assert conn.status == 422
      assert Map.has_key?(Jason.decode!(conn.resp_body)["errors"], "custom_fields.order_number")
      assert repo().aggregate(Ticket, :count) == 0
    end

    test "the camelCase customFields key keeps working", %{agent: agent, customer: customer} do
      field = field!("order_number", "text")

      conn =
        api_create(agent, %{
          "subject" => "API",
          "description" => "From the API",
          "requester_id" => customer.id,
          "requester_type" => "user",
          "customFields" => %{to_string(field.id) => "ORD-8"}
        })

      assert conn.status == 201
      assert stored(repo().one!(Ticket)) == %{"order_number" => "ORD-8"}
    end
  end
end
