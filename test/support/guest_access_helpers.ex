defmodule Escalated.Test.GuestAccessHelpers do
  @moduledoc false
  import ExUnit.Callbacks
  alias Escalated.Services.GuestAccess

  def configure do
    keys = [
      :guest_access_secret,
      :guest_verification_delivery,
      :guest_reference_resolver,
      :guest_access_ttl_minutes
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:escalated, &1)})
    parent = self()
    Application.put_env(:escalated, :guest_access_secret, String.duplicate("guest-test-key-", 5))

    Application.put_env(:escalated, :guest_verification_delivery, fn email, code, purpose ->
      send(parent, {:guest_code, email, code, purpose})
      :ok
    end)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  def proof(address \\ "recipient@example.test", purpose \\ "ticket") do
    {:ok, id} = GuestAccess.challenge(address, purpose)
    canonical = GuestAccess.email(address)

    receive do
      {:guest_code, ^canonical, code, ^purpose} ->
        %{"email" => address, "verification_id" => id, "verification_code" => code}
    after
      1000 -> raise "Expected trusted verification delivery"
    end
  end
end
