defmodule Escalated.Services.FollowersTest do
  use ExUnit.Case, async: true

  alias Escalated.Services.Followers

  describe "follower_recipients/2" do
    test "excludes the actor and de-duplicates, preserving order" do
      assert Followers.follower_recipients(["7", "2", "7", "3"], "2") == ["7", "3"]
    end

    test "keeps all (de-duplicated) when no actor is excluded" do
      assert Followers.follower_recipients(["7", "3", "7"], nil) == ["7", "3"]
    end

    test "coerces ids to strings before comparing" do
      assert Followers.follower_recipients([7, 2, 7], 2) == ["7"]
    end
  end
end
