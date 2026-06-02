defmodule Escalated.Repo.Migrations.NewsletterParityColumns do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table("#{@prefix}newsletter_deliveries") do
      add :next_attempt_at, :utc_datetime
    end

    alter table("#{@prefix}settings") do
      add :type, :string
    end
  end
end
