require "zip"

module Exporters
  # Markdown export (SPEC §11.2). Emits manual.md referencing ./images/step-NN.png,
  # bundled with the images as a zip — Markdown can't embed binary, and a zip keeps
  # it portable and editable.
  class Markdown < Base
    def self.format    = "markdown"
    def self.mime      = "text/markdown"
    def self.extension = "zip"

    def export(manual)
      items = steps_with_images(manual)
      md = render_markdown(manual, items)

      buffer = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("manual.md")
        zip.write(md)
        items.each do |item|
          next unless item[:image]

          zip.put_next_entry("images/#{item[:image_name]}")
          zip.write(item[:image])
        end
      end
      buffer.rewind

      Result.new(
        filename: "manual-#{manual.id}.zip",
        content_type: "application/zip",
        io: buffer
      )
    end

    # Exposed for golden-file tests (SPEC §15).
    def render_markdown(manual, items = steps_with_images(manual))
      lines = []
      lines << "# #{manual.title}"
      lines << ""
      lines << manual.summary.to_s unless manual.summary.blank?
      lines << ""
      items.each do |item|
        step = item[:step]
        lines << "## #{item[:index]}. #{step.title}"
        lines << ""
        lines << "![#{step.title}](./images/#{item[:image_name]})" if item[:image]
        lines << "" if item[:image]
        lines << step.body_markdown.to_s
        lines << ""
      end
      "#{lines.join("\n").strip}\n"
    end
  end
end
