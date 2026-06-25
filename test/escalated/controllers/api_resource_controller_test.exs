defmodule Escalated.Controllers.Api.ResourceControllerTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{Article, Tag}

  defp repo, do: Escalated.repo()

  test "the api resource controller is compiled" do
    assert Code.ensure_loaded?(Escalated.Controllers.Api.ResourceController)
  end

  test "published-article filtering + tags back the endpoints" do
    {:ok, _} =
      %Article{}
      |> Article.changeset(%{title: "Public", status: "published", body: "x"})
      |> repo().insert()

    {:ok, _} =
      %Article{}
      |> Article.changeset(%{title: "Draft", status: "draft", body: "y"})
      |> repo().insert()

    {:ok, _} = %Tag{} |> Tag.changeset(%{name: "billing"}) |> repo().insert()

    assert [%{title: "Public"}] = Article.published() |> repo().all()
    assert [%{name: "billing"}] = repo().all(Tag)
  end
end
