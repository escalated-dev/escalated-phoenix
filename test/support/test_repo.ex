defmodule Escalated.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :escalated,
    adapter: Ecto.Adapters.SQLite3
end
