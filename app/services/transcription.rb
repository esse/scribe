# Transcription namespace (SPEC §2, §9.3). Speech-to-text is provider-abstracted
# because the Anthropic API has no STT. Error classes live here so providers can
# raise them regardless of load order.
module Transcription
  # Provider misconfiguration (e.g. a missing API key).
  class ConfigurationError < StandardError; end

  # The provider returned an error / unexpected response.
  class TranscriptionError < StandardError; end
end
