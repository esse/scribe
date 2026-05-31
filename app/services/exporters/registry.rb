module Exporters
  # Drop-in format registry (SPEC §11.1). Built-ins register at boot; the API
  # exposes Registry.formats so the UI is data-driven.
  class Registry
    class << self
      def register(klass)
        table[klass.format] = klass
      end

      def for(format)
        table.fetch(format.to_s) { raise UnknownFormat, format }
      end

      def formats
        table.keys
      end

      def table
        @table ||= {}
      end

      def reset!
        @table = {}
      end
    end
  end
end
