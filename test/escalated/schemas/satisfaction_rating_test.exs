defmodule Escalated.Schemas.SatisfactionRatingTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{SatisfactionRating, Ticket}
  alias Escalated.Services.SettingsService

  defp repo, do: Escalated.repo()

  defp insert_ticket!(attrs \\ %{}) do
    {:ok, t} =
      %Ticket{}
      |> Ticket.changeset(Map.merge(%{subject: "S", description: "D", status: "resolved"}, attrs))
      |> repo().insert()

    t
  end

  defp changeset(attrs), do: SatisfactionRating.changeset(%SatisfactionRating{}, attrs)

  describe "changeset/2" do
    test "accepts a rating within 1..5" do
      assert changeset(%{ticket_id: 1, rating: 5}).valid?
    end

    test "rejects a rating outside 1..5" do
      refute changeset(%{ticket_id: 1, rating: 6}).valid?
      refute changeset(%{ticket_id: 1, rating: 0}).valid?
    end

    test "requires ticket_id and rating" do
      refute changeset(%{}).valid?
    end

    test "rejects an over-long comment" do
      refute changeset(%{ticket_id: 1, rating: 3, comment: String.duplicate("x", 2001)}).valid?
    end

    test "stamps created_at on insert" do
      assert Ecto.Changeset.get_field(changeset(%{ticket_id: 1, rating: 4}), :created_at)
    end
  end

  describe "one rating per ticket" do
    test "the unique constraint on ticket_id rejects a second rating" do
      ticket = insert_ticket!()

      assert {:ok, _} =
               %SatisfactionRating{}
               |> SatisfactionRating.changeset(%{ticket_id: ticket.id, rating: 5})
               |> repo().insert()

      assert {:error, cs} =
               %SatisfactionRating{}
               |> SatisfactionRating.changeset(%{ticket_id: ticket.id, rating: 4})
               |> repo().insert()

      refute cs.valid?
    end
  end

  describe "CSAT settings round-trip" do
    test "set then get_or_default reflects the stored value" do
      assert SettingsService.get_or_default("csat_scale", "1-5") == "1-5"
      SettingsService.set("csat_scale", "1-3", "csat")
      assert SettingsService.get_or_default("csat_scale", "1-5") == "1-3"
    end
  end

  describe "modules load" do
    test "the CSAT controllers are compiled" do
      assert Code.ensure_loaded?(Escalated.Controllers.SatisfactionRatingController)
      assert Code.ensure_loaded?(Escalated.Controllers.Admin.CsatSettingsController)
    end
  end
end
