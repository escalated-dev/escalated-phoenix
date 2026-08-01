defmodule Escalated.Services.CannedResponseServiceTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.CannedResponse
  alias Escalated.Services.CannedResponseService

  defp repo, do: Escalated.repo()

  defp insert!(attrs) do
    {:ok, response} =
      %CannedResponse{}
      |> CannedResponse.changeset(attrs)
      |> repo().insert()

    response
  end

  describe "create/2" do
    test "persists a canned response" do
      assert {:ok, response} =
               CannedResponseService.create(repo(), %{
                 "title" => "Greeting",
                 "body" => "Hi there!",
                 "created_by" => 5
               })

      assert response.id
      assert response.title == "Greeting"
      assert response.is_shared == true
    end

    test "returns an error changeset when required fields are missing" do
      assert {:error, changeset} = CannedResponseService.create(repo(), %{"title" => "no body"})
      refute changeset.valid?
    end
  end

  describe "update/3 and delete/2" do
    test "updates an existing response" do
      response = insert!(%{title: "Old", body: "old body"})

      assert {:ok, updated} =
               CannedResponseService.update(repo(), response, %{"title" => "New"})

      assert updated.title == "New"
    end

    test "deletes a response" do
      response = insert!(%{title: "Doomed", body: "bye"})
      assert {:ok, _} = CannedResponseService.delete(repo(), response)
      assert CannedResponseService.find_by_id(repo(), response.id) == nil
    end
  end

  describe "list/1" do
    test "returns every response, title-ordered" do
      insert!(%{title: "Bravo", body: "b", is_shared: false, created_by: 1})
      insert!(%{title: "Alpha", body: "a", is_shared: true, created_by: 2})

      titles = CannedResponseService.list(repo()) |> Enum.map(& &1.title)
      assert titles == ["Alpha", "Bravo"]
    end
  end

  describe "list_shared/1" do
    test "returns only shared responses" do
      insert!(%{title: "Shared", body: "s", is_shared: true, created_by: 1})
      insert!(%{title: "Private", body: "p", is_shared: false, created_by: 2})

      titles = CannedResponseService.list_shared(repo()) |> Enum.map(& &1.title)
      assert titles == ["Shared"]
    end
  end

  describe "list_for_agent/2" do
    test "returns shared responses plus the agent's own, excluding others' private" do
      insert!(%{title: "Shared one", body: "s", is_shared: true, created_by: 1})
      insert!(%{title: "Mine", body: "m", is_shared: false, created_by: 7})
      insert!(%{title: "Someone else private", body: "x", is_shared: false, created_by: 99})

      titles = CannedResponseService.list_for_agent(repo(), 7) |> Enum.map(& &1.title)
      assert "Shared one" in titles
      assert "Mine" in titles
      refute "Someone else private" in titles
    end
  end
end
