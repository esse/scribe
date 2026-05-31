module Exporters
  # Exporter contract (SPEC §11.1). Adding a format = write one subclass + register.
  class Base
    def self.format     = raise(NotImplementedError)
    def self.mime       = raise(NotImplementedError)
    def self.extension  = raise(NotImplementedError)

    # Returns an Exporters::Result.
    def export(manual) = raise(NotImplementedError)

    private

    # Steps with their resolved image bytes, in order. Keeps subclasses out of
    # storage details.
    def steps_with_images(manual)
      manual.steps.map.with_index(1) do |step, i|
        image = step.frame&.storage_key && Storage.exists?(step.frame.storage_key) ? Storage.get(step.frame.storage_key) : nil
        { index: i, step:, image:, image_name: format("step-%02d.png", i) }
      end
    end
  end
end
