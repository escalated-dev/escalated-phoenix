defmodule Escalated.Schemas.PluginTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.Plugin

  defp repo, do: Escalated.repo()

  defp insert_plugin!(attrs) do
    {:ok, plugin} =
      %Plugin{}
      |> Plugin.changeset(attrs)
      |> repo().insert()

    plugin
  end

  describe "changeset/2" do
    test "casts allowed fields and requires slug" do
      cs = Plugin.changeset(%Plugin{}, %{slug: "billing", is_active: true})

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :slug) == "billing"
      assert Ecto.Changeset.get_field(cs, :is_active) == true
    end

    test "is invalid without a slug" do
      refute Plugin.changeset(%Plugin{}, %{is_active: true}).valid?
    end

    test "defaults is_active to false" do
      plugin = insert_plugin!(%{slug: "analytics"})
      assert plugin.is_active == false
    end
  end

  describe "active/1" do
    test "returns only activated plugins, ordered by slug" do
      insert_plugin!(%{slug: "zeta", is_active: true})
      insert_plugin!(%{slug: "alpha", is_active: true})
      insert_plugin!(%{slug: "inactive", is_active: false})

      slugs = Plugin |> Plugin.active() |> repo().all() |> Enum.map(& &1.slug)
      assert slugs == ["alpha", "zeta"]
    end
  end

  describe "to_json/1" do
    test "exposes the expected fields" do
      plugin = insert_plugin!(%{slug: "billing", is_active: true})
      json = Plugin.to_json(plugin)

      assert json.slug == "billing"
      assert json.is_active == true
      assert Map.has_key?(json, :activated_at)
      assert Map.has_key?(json, :deactivated_at)
    end
  end
end
