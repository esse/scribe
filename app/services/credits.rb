# Credits namespace (SPEC §12, §13). The error class lives in the namespace file
# so callers can rescue Credits::InsufficientCredits independent of load order.
module Credits
  # Raised when a hold cannot be placed because the user lacks available credits
  # (SPEC §13.3 — caller turns this into a 402).
  class InsufficientCredits < StandardError
    attr_reader :required, :available

    def initialize(required:, available:)
      @required = required
      @available = available
      super("Insufficient credits: need #{required}, have #{available}")
    end
  end
end
