# Writes a finished manual out as plain files under the data dir, so results
# live on disk and travel with the mounted folder rather than being trapped in
# the database. Local-first: this is the canonical, portable copy of the result.
#
# Layout (under STORAGE_ROOT, i.e. the mounted data dir):
#   recordings/<id>/results/
#     manual.json          structured manual (title, summary, steps)
#     manual.md            readable Markdown, references images/step-NN.png
#     manual.html          self-contained HTML (images embedded)
#     manual.pdf           rendered PDF (best-effort; skipped if WeasyPrint absent)
#     transcript.json      the transcript + segment timings (when present)
#     images/step-NN.png   one screenshot per step
module ResultFiles
  module_function

  def write(manual)
    recording = manual.recording
    base = "recordings/#{recording.id}/results"

    write_json("#{base}/manual.json", manual_hash(manual))
    write_images(manual, base)
    write_text("#{base}/manual.md", Exporters::Markdown.new.render_markdown(manual), "text/markdown")
    write_text("#{base}/manual.html", Exporters::Html.new.render_html(manual), "text/html")
    write_pdf(manual, base)
    write_transcript(recording, base)

    base
  end

  # Absolute on-disk path to a recording's results folder (for the CLI to print).
  def results_path(recording)
    Storage.local_path("recordings/#{recording.id}/results/manual.json")&.then { |p| File.dirname(p) }
  end

  def manual_hash(manual)
    {
      id: manual.id,
      recording_id: manual.recording_id,
      title: manual.title,
      summary: manual.summary,
      model: manual.model,
      generated_at: manual.generated_at,
      steps: manual.steps.order(:position).map do |step|
        {
          position: step.position,
          title: step.title,
          body_markdown: step.body_markdown,
          source_start_ms: step.source_start_ms,
          source_end_ms: step.source_end_ms,
          image: step.frame ? "images/step-#{format('%02d', step.position + 1)}.png" : nil
        }
      end
    }
  end

  def write_images(manual, base)
    manual.steps.order(:position).each_with_index do |step, i|
      frame = step.frame
      next unless frame&.storage_key && Storage.exists?(frame.storage_key)

      Storage.put("#{base}/images/step-#{format('%02d', i + 1)}.png", StringIO.new(Storage.get(frame.storage_key)), content_type: "image/png")
    end
  end

  def write_pdf(manual, base)
    result = Exporters::Pdf.new.export(manual)
    Storage.put("#{base}/manual.pdf", result.io, content_type: "application/pdf")
  rescue Exporters::Pdf::RendererUnavailable => e
    Rails.logger.info(tag: "result_files", message: "Skipping PDF: #{e.message}")
  end

  def write_transcript(recording, base)
    transcript = recording.transcript
    return unless transcript

    write_json("#{base}/transcript.json", {
      provider: transcript.provider,
      language: transcript.language,
      full_text: transcript.full_text,
      segments: transcript.segments.order(:position).map { |s| { start_ms: s.start_ms, end_ms: s.end_ms, text: s.text } }
    })
  end

  def write_json(key, hash)
    Storage.put(key, StringIO.new(JSON.pretty_generate(hash)), content_type: "application/json")
  end

  def write_text(key, text, content_type)
    Storage.put(key, StringIO.new(text.to_s), content_type:)
  end
end
