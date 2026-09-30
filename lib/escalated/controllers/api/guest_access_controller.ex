defmodule Escalated.Controllers.Api.GuestAccessController do
  use Phoenix.Controller, formats: [:json]
  defdelegate challenge(conn, params), to: Escalated.Controllers.GuestAccessController
  defdelegate lookup(conn, params), to: Escalated.Controllers.GuestAccessController
end
