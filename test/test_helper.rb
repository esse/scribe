ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Parallel workers share the filesystem but have separate databases (so record
    # ids can collide). Give each worker its own object-storage and tus directories
    # so tests that write to the same storage key can't clobber each other.
    parallelize_setup do |worker|
      Scribe.config.storage_root = Rails.root.join("tmp/test_storage/worker-#{worker}").to_s
      Storage.reset!
      ENV["TUS_DATA_DIR"] = Rails.root.join("tmp/test_tus/worker-#{worker}").to_s
    end

    parallelize_teardown do |worker|
      FileUtils.rm_rf(Rails.root.join("tmp/test_storage/worker-#{worker}"))
      FileUtils.rm_rf(Rails.root.join("tmp/test_tus/worker-#{worker}"))
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
