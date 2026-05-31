require "test_helper"

# Ledger correctness (SPEC §12, §13, §15): balance math, hold→settle/void, and
# no double-spend under concurrency.
class CreditTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "available balance counts settled and pending, excludes void" do
    Credits::Ledger.grant_purchase!(user: @user, credits: 100, stripe_session_id: "cs_test_1")
    assert_equal 100, @user.available_credits

    hold = Credits::Ledger.hold!(user: @user, amount: 30, reference: nil)
    assert_equal 70, @user.available_credits, "pending hold reduces available immediately"

    Credits::Ledger.void!(hold)
    assert_equal 100, @user.available_credits, "voided hold no longer counts"
  end

  test "settle keeps the hold counted at actual cost, never above estimate" do
    Credits::Ledger.grant_purchase!(user: @user, credits: 100, stripe_session_id: "cs_test_2")
    hold = Credits::Ledger.hold!(user: @user, amount: 40, reference: nil)

    Credits::Ledger.settle!(hold, actual_amount: 25)
    assert hold.reload.settled?
    assert_equal(-25, hold.amount, "settles to actual, lower than the 40 estimate")
    assert_equal 75, @user.available_credits
  end

  test "settle cannot exceed the reserved estimate" do
    Credits::Ledger.grant_purchase!(user: @user, credits: 100, stripe_session_id: "cs_test_3")
    hold = Credits::Ledger.hold!(user: @user, amount: 20, reference: nil)

    Credits::Ledger.settle!(hold, actual_amount: 999)
    assert_equal(-20, hold.reload.amount, "never charges more than the hold")
  end

  test "hold raises InsufficientCredits when balance is short" do
    Credits::Ledger.grant_purchase!(user: @user, credits: 10, stripe_session_id: "cs_test_4")
    error = assert_raises(Credits::InsufficientCredits) do
      Credits::Ledger.hold!(user: @user, amount: 50, reference: nil)
    end
    assert_equal 50, error.required
    assert_equal 10, error.available
    assert_equal 10, @user.available_credits, "no hold row is left behind on failure"
  end

  test "purchase grant is idempotent on stripe_session_id" do
    2.times { Credits::Ledger.grant_purchase!(user: @user, credits: 60, stripe_session_id: "cs_dupe") }
    assert_equal 1, @user.credit_transactions.where(stripe_session_id: "cs_dupe").count
    assert_equal 60, @user.available_credits
  end
end

# Concurrency needs real cross-connection commits, so transactional fixtures are
# off here and rows are cleaned up manually (SPEC §15: no double-spend).
class CreditLedgerConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @user = users(:one)
    @user.credit_transactions.delete_all
    Credits::Ledger.grant_purchase!(user: @user, credits: 100, stripe_session_id: "cs_conc")
  end

  teardown do
    @user.credit_transactions.delete_all
  end

  test "concurrent holds cannot overspend the balance" do
    successes = Concurrent::Array.new
    failures = Concurrent::Array.new

    threads = 10.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Credits::Ledger.hold!(user: User.find(@user.id), amount: 20, reference: nil)
          successes << true
        rescue Credits::InsufficientCredits
          failures << true
        end
      end
    end
    threads.each(&:join)

    assert_equal 5, successes.size, "exactly five 20-credit holds fit in 100"
    assert_equal 5, failures.size
    assert_equal 0, @user.available_credits
  end
end
