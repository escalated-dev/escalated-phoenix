defmodule Escalated.Controllers.Admin.CannedResponseControllerTest do
  @moduledoc """
  Exercises the admin canned-response CRUD surface (mirrors the automation /
  macro admin controllers).
  """
  use Escalated.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias Escalated.Controllers.Admin.CannedResponseController
  alias Escalated.Schemas.CannedResponse

  defp repo, do: Escalated.repo()

  defp conn!(agent_id \\ nil) do
    conn(:post, "/")
    |> init_test_session(%{})
    |> Phoenix.Controller.fetch_flash()
    |> maybe_assign_agent(agent_id)
  end

  defp maybe_assign_agent(conn, nil), do: conn
  defp maybe_assign_agent(conn, id), do: assign(conn, :current_user, %{id: id})

  describe "module interface" do
    test "exposes the CRUD actions mirrored from the macro admin controller" do
      assert function_exported?(CannedResponseController, :index, 2)
      assert function_exported?(CannedResponseController, :show, 2)
      assert function_exported?(CannedResponseController, :create, 2)
      assert function_exported?(CannedResponseController, :update, 2)
      assert function_exported?(CannedResponseController, :delete, 2)
    end
  end

  describe "create/2" do
    test "persists a canned response and stamps the current agent as creator" do
      conn =
        CannedResponseController.create(conn!(7), %{
          "title" => "Refund acknowledged",
          "body" => "Your refund is on its way.",
          "category" => "Billing"
        })

      assert conn.status == 302

      response = repo().get_by(CannedResponse, title: "Refund acknowledged")
      assert response.body == "Your refund is on its way."
      assert response.category == "Billing"
      assert response.created_by == 7
      assert response.is_shared == true
    end

    test "rejects an invalid canned response with a 422" do
      conn = CannedResponseController.create(conn!(7), %{"title" => "no body"})

      assert conn.status == 422
      assert repo().all(CannedResponse) == []
    end
  end

  describe "update/2" do
    test "edits an existing canned response" do
      {:ok, response} =
        %CannedResponse{}
        |> CannedResponse.changeset(%{title: "Old", body: "old body", created_by: 7})
        |> repo().insert()

      conn =
        CannedResponseController.update(conn!(7), %{
          "id" => to_string(response.id),
          "title" => "New title",
          "body" => "new body"
        })

      assert conn.status == 302

      reloaded = repo().get(CannedResponse, response.id)
      assert reloaded.title == "New title"
      assert reloaded.body == "new body"
    end
  end

  describe "delete/2" do
    test "removes the canned response" do
      {:ok, response} =
        %CannedResponse{}
        |> CannedResponse.changeset(%{title: "Doomed", body: "bye"})
        |> repo().insert()

      conn = CannedResponseController.delete(conn!(), %{"id" => to_string(response.id)})
      assert conn.status == 302
      assert repo().get(CannedResponse, response.id) == nil
    end
  end

  describe "show/2 (not found)" do
    test "returns 404 for a missing canned response" do
      conn = CannedResponseController.show(conn!(), %{"id" => "9999999"})
      assert conn.status == 404
    end
  end
end
