defmodule Escalated.StaffAuthorizationTest do
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Channels.{ChatChannel, TicketChannel}
  alias Escalated.Permissions
  alias Escalated.Schemas.AgentProfile
  alias Escalated.Services.Newsletter.Permission
  alias Escalated.Services.TicketService
  alias Escalated.Test.Router

  setup do
    previous =
      Map.new(
        [:admin_check, :agent_check, :newsletter_permission_check],
        &{&1, Application.fetch_env(:escalated, &1)}
      )

    Enum.each(Map.keys(previous), &Application.delete_env(:escalated, &1))

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "default staff predicates agree across HTTP and channel joins" do
    for {user, admin?, agent?} <- [
          {nil, false, false},
          {%{id: 11}, false, false},
          {%{id: 12, is_agent: true}, false, true},
          {%{id: 13, is_admin: true}, true, true},
          {%{"id" => "14", "is_agent" => "1"}, false, true}
        ] do
      assert Permissions.admin?(user) == admin?
      assert Permissions.agent?(user) == agent?
      conn = request(:get, "/support/agent/chat/sessions", user)
      assert conn.status == if(agent?, do: 200, else: if(is_nil(user), do: 401, else: 403))
      assert allowed?(TicketChannel.join("escalated:tickets", %{}, socket(user))) == agent?
      assert allowed?(ChatChannel.join("escalated:chat:queue", %{}, socket(user))) == agent?
    end
  end

  test "only finite host flag values grant access and atom keys take precedence" do
    for value <- [false, 0, "0", "false", nil, :error, [], %{}] do
      refute Permissions.agent?(%{id: 10, is_agent: value})
      refute Permissions.admin?(%{id: 10, is_admin: value})
    end

    for value <- [true, 1, "1", "true"] do
      assert Permissions.agent?(%{id: 10, is_agent: value})
      assert Permissions.admin?(%{id: 10, is_admin: value})
    end

    refute Permissions.agent?(%{"is_agent" => true, id: 10, is_agent: false})

    for user <- [nil, %{}, %{id: nil, is_admin: true}, %{id: "", is_agent: true}, "invalid"] do
      refute Permissions.agent?(user)
      refute Permissions.admin?(user)
    end
  end

  test "callback decisions are strict, authoritative and capability-specific" do
    user = %{id: 10, is_agent: true, is_admin: true}

    for value <- [false, nil, :error, {:error, :denied}, "false", 0] do
      Application.put_env(:escalated, :agent_check, fn _ -> value end)
      Application.put_env(:escalated, :admin_check, fn _ -> value end)
      refute Permissions.admin?(user)
      refute Permissions.agent?(user)
      assert request(:get, "/support/agent/chat/sessions", user).status == 403
      refute allowed?(TicketChannel.join("escalated:tickets", %{}, socket(user)))
    end

    for bad <- [:invalid, fn -> true end] do
      Application.put_env(:escalated, :agent_check, bad)
      Application.put_env(:escalated, :admin_check, bad)
      refute Permissions.admin?(user)
      refute Permissions.agent?(user)
    end

    Application.put_env(:escalated, :admin_check, fn _ -> true end)
    Application.put_env(:escalated, :agent_check, fn _ -> false end)
    assert Permissions.admin?(user)
    refute Permissions.agent?(user)
    Application.put_env(:escalated, :agent_check, fn _ -> true end)
    assert Permissions.agent?(%{id: 15})
    refute Permissions.agent?(nil)
    refute Permissions.admin?(%{})
  end

  test "active profiles grant staff roles and deactivation removes profile-derived access" do
    for {id, role} <- [{21, "agent"}, {22, "admin"}] do
      profile =
        %AgentProfile{}
        |> AgentProfile.changeset(%{user_id: id, role: role, is_active: true})
        |> Escalated.repo().insert!()

      assert Permissions.agent?(%{id: id})
      assert Permissions.admin?(%{id: id}) == (role == "admin")
      assert allowed?(ChatChannel.join("escalated:chat:queue", %{}, socket(%{id: id})))
      profile |> AgentProfile.changeset(%{is_active: false}) |> Escalated.repo().update!()
      refute Permissions.agent?(%{id: id})
      refute Permissions.admin?(%{id: id})
      assert Permissions.agent?(%{id: id, is_agent: true})
    end
  end

  test "ticket ownership remains available without granting staff channels" do
    {:ok, ticket} =
      TicketService.create(%{
        subject: "Ownership",
        description: "Body",
        requester_id: 31,
        requester_type: "user"
      })

    assert allowed?(TicketChannel.join("escalated:ticket:#{ticket.id}", %{}, socket(%{id: 31})))
    refute allowed?(TicketChannel.join("escalated:ticket:#{ticket.id}", %{}, socket(%{id: 32})))
    refute allowed?(TicketChannel.join("escalated:agent:31", %{}, socket(%{id: 31})))

    assert allowed?(
             TicketChannel.join("escalated:agent:31", %{}, socket(%{id: 31, is_agent: true}))
           )

    refute allowed?(
             TicketChannel.join("escalated:agent:32", %{}, socket(%{id: 31, is_agent: true}))
           )

    for id <- ["not-a-number", "0", "999999999999999999999999"] do
      refute allowed?(TicketChannel.join("escalated:ticket:#{id}", %{}, socket(%{id: 31})))
    end
  end

  test "guest chat joins reject obsolete raw tokens even when the stored token matches" do
    for stored <- [nil, "", "guest-secret"] do
      {:ok, ticket} =
        TicketService.create(%{
          subject: "Chat",
          description: "Body",
          channel: "chat",
          guest_token: stored
        })

      for supplied <- [nil, "", "wrong", [], %{}, "guest-secret"] do
        result =
          ChatChannel.join(
            "escalated:chat:#{ticket.id}",
            %{"guest_token" => supplied},
            socket(nil)
          )

        refute allowed?(result)
      end

      assert allowed?(
               ChatChannel.join(
                 "escalated:chat:#{ticket.id}",
                 %{"guest_token" => nil},
                 socket(%{id: 40, is_agent: true})
               )
             )
    end

    {:ok, email} =
      TicketService.create(%{
        subject: "Email",
        description: "Body",
        channel: "email",
        guest_token: "guest-secret"
      })

    refute allowed?(
             ChatChannel.join(
               "escalated:chat:#{email.id}",
               %{"guest_token" => "guest-secret"},
               socket(nil)
             )
           )

    for id <- ["missing", "999999999999999999999999", "0", "999999"] do
      refute allowed?(
               ChatChannel.join("escalated:chat:#{id}", %{}, socket(%{id: 40, is_agent: true}))
             )
    end
  end

  test "chat queue is always a staff topic regardless of a guest-token field" do
    for params <- [nil, "invalid", [], 1] do
      refute allowed?(ChatChannel.join("escalated:chat:1", params, socket(nil)))
    end

    for params <- [%{}, %{"guest_token" => nil}, %{"guest_token" => "guest-secret"}] do
      refute allowed?(ChatChannel.join("escalated:chat:queue", params, socket(nil)))
      refute allowed?(ChatChannel.join("escalated:chat:queue", params, socket(%{id: 1})))

      assert allowed?(
               ChatChannel.join("escalated:chat:queue", params, socket(%{id: 1, is_agent: true}))
             )
    end
  end

  test "newsletter permission callbacks are strict and take precedence over admin fallback" do
    user = %{id: 1, is_admin: true}
    assert Permission.allowed?(user, "newsletters.manage")

    for result <- [false, nil, "false", :error] do
      Application.put_env(:escalated, :newsletter_permission_check, fn _, _ -> result end)
      refute Permission.allowed?(user, "newsletters.manage")
    end

    Application.put_env(:escalated, :newsletter_permission_check, fn _, _ -> true end)
    assert Permission.allowed?(%{id: 2}, "newsletters.manage")
    refute Permission.allowed?(nil, "newsletters.manage")
  end

  defp request(method, path, user) do
    conn(method, path)
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> put_req_header("accept", "application/json")
    |> Router.call(Router.init([]))
  end

  defp socket(user), do: %Phoenix.Socket{assigns: %{current_user: user}}
  defp allowed?({:ok, _}), do: true
  defp allowed?({:error, _}), do: false
end
