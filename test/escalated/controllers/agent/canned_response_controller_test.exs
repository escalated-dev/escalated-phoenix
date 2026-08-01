defmodule Escalated.Controllers.Agent.CannedResponseControllerTest do
  @moduledoc """
  The agent-facing list returns shared canned responses plus the agent's own.
  """
  use Escalated.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias Escalated.Controllers.Agent.CannedResponseController
  alias Escalated.Schemas.CannedResponse

  defp repo, do: Escalated.repo()

  defp conn!(agent_id) do
    conn(:get, "/")
    |> init_test_session(%{})
    |> assign(:current_user, %{id: agent_id})
  end

  defp insert!(attrs) do
    {:ok, response} =
      %CannedResponse{}
      |> CannedResponse.changeset(attrs)
      |> repo().insert()

    response
  end

  describe "module interface" do
    test "exposes an index action" do
      assert function_exported?(CannedResponseController, :index, 2)
    end
  end

  describe "index/2" do
    test "returns shared responses plus the agent's own, as JSON" do
      insert!(%{title: "Shared", body: "s", is_shared: true, created_by: 1})
      insert!(%{title: "Mine", body: "m", is_shared: false, created_by: 7})
      insert!(%{title: "Other private", body: "x", is_shared: false, created_by: 99})

      conn = CannedResponseController.index(conn!(7), %{})

      assert conn.status == 200
      titles = conn.resp_body |> Jason.decode!() |> Enum.map(& &1["title"])

      assert "Shared" in titles
      assert "Mine" in titles
      refute "Other private" in titles
    end
  end
end
