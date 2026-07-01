defmodule Escalated.Plugins.StoreTest do
  use Escalated.DataCase, async: false

  alias Escalated.Plugins.Store

  describe "set/4 and get/3" do
    test "stores and retrieves a keyed data map" do
      {:ok, _} = Store.set("billing", "invoices", "inv_1", %{"amount" => 50})
      assert Store.get("billing", "invoices", "inv_1") == %{"amount" => 50}
    end

    test "returns nil for a missing key" do
      assert Store.get("billing", "invoices", "nope") == nil
    end

    test "overwrites an existing key without inserting a duplicate" do
      {:ok, _} = Store.set("billing", "invoices", "inv_1", %{"amount" => 50})
      {:ok, _} = Store.set("billing", "invoices", "inv_1", %{"amount" => 75})

      assert Store.get("billing", "invoices", "inv_1") == %{"amount" => 75}
      assert length(Store.query("billing", "invoices")) == 1
    end
  end

  describe "query/3" do
    setup do
      {:ok, _} = Store.set("billing", "invoices", "a", %{"amount" => 10, "status" => "paid"})
      {:ok, _} = Store.set("billing", "invoices", "b", %{"amount" => 50, "status" => "paid"})
      {:ok, _} = Store.set("billing", "invoices", "c", %{"amount" => 90, "status" => "due"})
      :ok
    end

    test "returns all entries with no filter" do
      assert length(Store.query("billing", "invoices")) == 3
    end

    test "filters by equality" do
      results = Store.query("billing", "invoices", %{"status" => "paid"})
      assert length(results) == 2
    end

    test "filters with comparison operators" do
      results = Store.query("billing", "invoices", %{"amount" => %{"$gte" => 50}})
      amounts = results |> Enum.map(& &1["amount"]) |> Enum.sort()
      assert amounts == [50, 90]
    end

    test "filters with $in" do
      results = Store.query("billing", "invoices", %{"amount" => %{"$in" => [10, 90]}})
      assert length(results) == 2
    end

    test "scopes to the plugin and collection" do
      {:ok, _} = Store.set("other", "invoices", "x", %{"amount" => 999})
      assert length(Store.query("billing", "invoices")) == 3
    end
  end

  describe "insert/3 and delete/3" do
    test "insert appends a keyless entry" do
      {:ok, _} = Store.insert("analytics", "events", %{"type" => "click"})
      {:ok, _} = Store.insert("analytics", "events", %{"type" => "view"})
      assert length(Store.query("analytics", "events")) == 2
    end

    test "delete removes a keyed entry and is a no-op when absent" do
      {:ok, _} = Store.set("billing", "invoices", "a", %{"amount" => 10})
      {:ok, _} = Store.delete("billing", "invoices", "a")
      assert Store.get("billing", "invoices", "a") == nil
      assert {:ok, nil} = Store.delete("billing", "invoices", "a")
    end
  end
end
