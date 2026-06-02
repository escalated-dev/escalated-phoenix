defmodule Escalated.Plugs.EnsureNewslettersEnabledTest do
  use ExUnit.Case, async: true

  import Plug.Test
  alias Escalated.Plugs.EnsureNewslettersEnabled

  test "returns 404 when disabled" do
    Application.put_env(:escalated, :enable_newsletters, false)
    conn = conn(:get, "/escalated/n/o/x") |> EnsureNewslettersEnabled.call([])
    assert conn.status == 404
  end
end
