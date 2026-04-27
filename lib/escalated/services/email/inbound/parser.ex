defmodule Escalated.Services.Email.Inbound.Parser do
  @moduledoc """
  Behaviour for transport-specific inbound email parsers. Implement
  this in host apps (or the package's provider-specific adapters) to
  normalize a provider's webhook payload into an
  `Escalated.Services.Email.Inbound.Message`.

  `name/0` must match the adapter label on the inbound webhook
  request (matching on the `adapter` query param or
  `x-escalated-adapter` header).
  """

  alias Escalated.Services.Email.Inbound.Message

  @callback name() :: String.t()
  @callback parse(raw_payload :: map()) :: {:ok, Message.t()} | {:error, term()}
end
