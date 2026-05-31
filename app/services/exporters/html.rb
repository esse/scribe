module Exporters
  # HTML export (SPEC §11.2): one portable, self-contained .html with
  # base64-embedded images. Also the layout source the PDF exporter composes.
  class Html < Base
    def self.format    = "html"
    def self.mime      = "text/html"
    def self.extension = "html"

    def export(manual)
      Result.new(
        filename: "manual-#{manual.id}.html",
        content_type: "text/html",
        io: StringIO.new(render_html(manual))
      )
    end

    # Exposed so the PDF exporter and tests can reuse the rendered document.
    def render_html(manual, items = steps_with_images(manual))
      steps_html = items.map do |item|
        step = item[:step]
        img =
          if item[:image]
            data = Base64.strict_encode64(item[:image])
            %(<img src="data:image/png;base64,#{data}" alt="#{h(step.title)}">)
          else
            ""
          end
        <<~STEP
          <section class="step">
            <h2>#{item[:index]}. #{h(step.title)}</h2>
            #{img}
            <div class="body">#{paragraphs(step.body_markdown)}</div>
          </section>
        STEP
      end.join("\n")

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <title>#{h(manual.title)}</title>
        <style>
          body { font-family: -apple-system, Segoe UI, Roboto, sans-serif; max-width: 760px; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; }
          h1 { font-size: 2rem; }
          .summary { color: #555; font-size: 1.1rem; }
          .step { margin: 2rem 0; }
          .step img { max-width: 100%; border: 1px solid #ddd; border-radius: 6px; }
          .step h2 { border-bottom: 1px solid #eee; padding-bottom: .25rem; }
        </style>
        </head>
        <body>
        <h1>#{h(manual.title)}</h1>
        <p class="summary">#{h(manual.summary)}</p>
        #{steps_html}
        </body>
        </html>
      HTML
    end

    private

    def h(text) = ERB::Util.html_escape(text.to_s)

    def paragraphs(markdown)
      markdown.to_s.split(/\n{2,}/).map { |p| "<p>#{h(p.strip)}</p>" }.join("\n")
    end
  end
end
