require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "User.local returns the single implicit user" do
    assert_equal User.first, User.local
    assert_equal User.local, User.local, "stable across calls"
  end

  test "User.local creates a user when none exists" do
    User.delete_all
    assert_difference -> { User.count }, 1 do
      assert User.local.persisted?
    end
  end
end
