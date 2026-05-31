module Exporters
  # PDF export (SPEC §11.2): composes the HTML exporter and renders it with
  # WeasyPrint. WeasyPrint is a lightweight HTML/CSS → PDF engine (no headless
  # browser), wrapped here as a CLI that reads HTML on stdin and writes the PDF
  # on stdout. The HTML is fully self-contained (images are base64 data URIs),
  # so no base URL or network access is needed.
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

    # Configurable command (ENV WEASYPRINT_CMD), e.g. "weasyprint" or
    # "python3 -m weasyprint". "-" "-" = read HTML from stdin, write PDF to stdout.
    def render(html)
      cmd = Scribe.config.weasyprint_cmd
      out, err, status = Open3.capture3(*cmd, "-", "-", stdin_data: html, binmode: true)
      raise RendererUnavailable, "WeasyPrint failed: #{err}" unless status.success? && out.start_with?("%PDF")

      out
    rescue Errno::ENOENT => e
      # Binary missing (e.g. minimal CI) — ExportJob marks the export failed and
      # the smoke test skips, rather than crashing opaquely.
      raise RendererUnavailable, "WeasyPrint not installed (set WEASYPRINT_CMD): #{e.message}"
    end
  end
end
