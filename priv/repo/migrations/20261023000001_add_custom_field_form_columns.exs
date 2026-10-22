defmodule Escalated.Repo.Migrations.AddCustomFieldFormColumns do
  @moduledoc """
  The custom field columns escalated-laravel has and this table did not:
  `placeholder`, `validation_rules` and `conditions`. The two JSON values are
  stored as text (`Escalated.Types.JsonText`), so the columns add and drop the
  same way on SQLite, PostgreSQL and MySQL. Existing rows get nil.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table(@prefix <> "custom_fields") do
      add :placeholder, :string
      add :validation_rules, :text
      add :conditions, :text
    end
  end
end
