defmodule Escalated.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Supervisor.start_link([Escalated.RateLimiter],
      strategy: :one_for_one,
      name: Escalated.Supervisor
    )
  end
end
