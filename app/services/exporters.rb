# Export system namespace (SPEC §11). Shared constants live here so Zeitwerk can
# resolve them independent of which exporter loads first.
module Exporters
  class UnknownFormat < StandardError; end

  # A produced artifact. `io` may be a zip (e.g. Markdown bundles images).
  Result = Struct.new(:filename, :content_type, :io, keyword_init: true)
end
