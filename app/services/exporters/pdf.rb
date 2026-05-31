module Exporters
  # PDF export (SPEC §11.2): composes the HTML exporter and renders it with
  # headless Chromium via grover. No separate PDF layout code.
  class Pdf < Base
    class RendererUnavailable < StandardError; end

    def self.format    = "pdf"
    def self.mime      = "application/pdf"
    def self.extension = "pdf"

    def export(manual)
      html = Exporters::Html.new.render_html(manual)
      pdf_bytes = render(html)

      Result.new(
        filename: "manual-#{manual.id}.pdf",
        content_type: "application/pdf",
        io: StringIO.new(pdf_bytes)
      )
    end

    private

    def render(html)
      require "grover"
      Grover.new(html, format: "A4", margin: { top: "1cm", bottom: "1cm", left: "1cm", right: "1cm" }).to_pdf
    rescue LoadError, StandardError => e
      # Chromium/puppeteer may be absent (e.g. minimal CI). Surface a clear error
      # so ExportJob marks the export failed rather than crashing opaquely.
      raise RendererUnavailable, "PDF rendering requires headless Chromium: #{e.message}"
    end
  end
end
