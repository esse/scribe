require "test_helper"
require "zip"

# Exporter tests (SPEC §15): golden Markdown/HTML, PDF smoke (renders non-empty,
# skipped when headless Chromium is unavailable).
class ExportersTest < ActiveSupport::TestCase
  # Smallest valid PNG (1x1, transparent).
  PNG_1X1 = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  ).freeze

  setup do
    user = users(:one)
    recording = user.recordings.create!(status: :complete, duration_seconds: 12.0)
    frame_key = "test/frames/frame.png"
    Storage.put(frame_key, StringIO.new(PNG_1X1), content_type: "image/png")
    frame = recording.frames.create!(timestamp_ms: 1000, storage_key: frame_key, source: :scene)

    @manual = Manual.create!(recording:, title: "How to Create a Project", summary: "A short walkthrough.", status: :ready)
    @manual.steps.create!(position: 0, title: "Open the dashboard", body_markdown: "Click **Dashboard** in the nav.", frame:)
    @manual.steps.create!(position: 1, title: "Create a project", body_markdown: "Press the New Project button.", frame:)
  end

  test "markdown exporter renders a golden document" do
    md = Exporters::Markdown.new.render_markdown(@manual)
    expected = <<~MD
      # How to Create a Project

      A short walkthrough.

      ## 1. Open the dashboard

      ![Open the dashboard](./images/step-01.png)

      Click **Dashboard** in the nav.

      ## 2. Create a project

      ![Create a project](./images/step-02.png)

      Press the New Project button.
    MD
    assert_equal expected, md
  end

  test "markdown export bundles md plus images in a zip" do
    result = Exporters::Markdown.new.export(@manual)
    assert_equal "application/zip", result.content_type

    entries = {}
    Zip::File.open_buffer(result.io) do |zip|
      zip.each { |e| entries[e.name] = e.get_input_stream.read }
    end
    assert_includes entries.keys, "manual.md"
    assert_includes entries.keys, "images/step-01.png"
    assert_includes entries.keys, "images/step-02.png"
    assert_equal PNG_1X1, entries["images/step-01.png"]
  end

  test "html exporter is self-contained with base64 images" do
    html = Exporters::Html.new.render_html(@manual)
    assert_includes html, "<title>How to Create a Project</title>"
    assert_includes html, "data:image/png;base64,#{Base64.strict_encode64(PNG_1X1)}"
    assert_includes html, "1. Open the dashboard"
    assert_includes html, "Press the New Project button."
  end

  test "html escapes user content" do
    @manual.update!(title: "Tom & Jerry <script>")
    html = Exporters::Html.new.render_html(@manual)
    assert_includes html, "Tom &amp; Jerry &lt;script&gt;"
    refute_includes html, "<script>"
  end

  test "pdf exporter renders a non-empty PDF (smoke)" do
    result = Exporters::Pdf.new.export(@manual)
    bytes = result.io.read
    assert_equal "application/pdf", result.content_type
    assert bytes.bytesize.positive?
    assert bytes.start_with?("%PDF"), "expected a PDF header"
  rescue Exporters::Pdf::RendererUnavailable => e
    skip "headless Chromium not available: #{e.message}"
  end

  test "registry resolves built-in formats and rejects unknown" do
    assert_equal %w[markdown html pdf], Exporters::Registry.formats
    assert_equal Exporters::Html, Exporters::Registry.for("html")
    assert_raises(Exporters::UnknownFormat) { Exporters::Registry.for("docx") }
  end
end
