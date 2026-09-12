defmodule Escalated.HostTestRepo do
  @moduledoc """
  Stands in for the host application's own repo.

  Escalated's tables live on `Escalated.TestRepo`; the host's `users` table
  lives here. Two repos means two databases, which is the only way to prove
  `Escalated.user_repo/0` actually reaches a different one -- a second repo
  pointed at the same file would pass every assertion and prove nothing.
  """
  use Ecto.Repo,
    otp_app: :escalated,
    adapter: Ecto.Adapters.SQLite3
end

defmodule Escalated.Test.HostUser do
  @moduledoc """
  A minimal host user schema, shaped like the columns Escalated reads:
  `name`, `email`, `is_admin` and `is_agent`.
  """
  use Ecto.Schema

  schema "users" do
    field(:name, :string)
    field(:email, :string)
    field(:is_admin, :boolean, default: false)
    field(:is_agent, :boolean, default: false)
  end
end
