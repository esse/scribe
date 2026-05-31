module Credits
  # v1 metering: flat per-minute (SPEC §13.3).
  #   estimate_credits = ceil(duration_seconds / 60.0) * CREDITS_PER_MINUTE
  module Meter
    module_function

    def estimate_for(recording)
      seconds = recording.duration_seconds.to_f
      minutes = (seconds / 60.0).ceil
      minutes = 1 if minutes < 1 # always charge at least one minute
      minutes * Scribe.config.credits_per_minute
    end
  end
end
