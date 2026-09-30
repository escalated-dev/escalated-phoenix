defmodule Escalated.Channels.TenantSocket do
  @moduledoc false

  alias Escalated.Tenancy

  # The host's authenticated Socket.connect/3 sets this assign. Neither a join
  # parameter nor a client-supplied topic can establish a merchant identity.
  def run(socket, callback, denied) do
    if Tenancy.enabled?() do
      run_tenant(socket, callback, denied)
    else
      callback.()
    end
  rescue
    _ -> denied
  end

  defp run_tenant(socket, callback, denied) do
    tenant_id = socket.assigns[:escalated_tenant_id]

    if is_binary(tenant_id) and tenant_id != "" do
      Tenancy.run(tenant_id, fn ->
        if Tenancy.member?(socket.assigns[:current_user]), do: callback.(), else: denied
      end)
    else
      denied
    end
  end

  def canonical_topic(topic) when is_binary(topic) do
    prefix = Tenancy.topic("escalated:")

    if String.starts_with?(topic, prefix) do
      "escalated:" <> binary_part(topic, byte_size(prefix), byte_size(topic) - byte_size(prefix))
    end
  end

  def canonical_topic(_), do: nil

  def remember({:ok, socket}, topic),
    do: {:ok, Phoenix.Socket.assign(socket, :escalated_joined_topic, topic)}

  def remember(result, _topic), do: result

  def joined_topic(socket), do: socket.assigns[:escalated_joined_topic] || socket.topic
end
