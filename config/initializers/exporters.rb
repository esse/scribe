# Register built-in exporters at boot (SPEC §11.1). Adding a format is a one-class
# change plus a line here.
Rails.application.config.to_prepare do
  Exporters::Registry.reset!
  Exporters::Registry.register(Exporters::Markdown)
  Exporters::Registry.register(Exporters::Html)
  Exporters::Registry.register(Exporters::Pdf)
end
