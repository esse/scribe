module ManualGeneration
  # Builds the Claude prompt from the transcript + candidate frames and returns
  # the structured manual (SPEC §8.5, §9). Long recordings are chunked by time
  # window so we stay within context limits and bound cost (SPEC §8.5).
  #
  # Returns: { title:, summary:, model:, usage:, steps: [{ title:, body_markdown:,
  #            source_start_ms:, source_end_ms:, frame_timestamp_ms: }] }
  class Generator
    Result = Struct.new(:title, :summary, :model, :usage, :steps, keyword_init: true)

    def initialize(recording:, client: nil, model: nil)
      @recording = recording
      @client = client || LLM.client
      @model = model || LLM.model
    end

    def call
      transcript = @recording.transcript
      frames = @recording.frames.order(:timestamp_ms).to_a
      chunks = chunk_segments(transcript.segments.to_a)

      all_steps = []
      usage = { input: 0, output: 0 }
      title = nil
      summary = nil

      chunks.each do |segments|
        result = generate_chunk(segments, frames)
        title ||= result["title"]
        summary ||= result["summary"]
        all_steps.concat(Array(result["steps"]))
        u = Anthropic::Client.token_usage(@last_response)
        usage[:input] += u[:input]
        usage[:output] += u[:output]
      end

      Result.new(
        title: title.presence || "User Manual",
        summary: summary.to_s,
        model: @model,
        usage:,
        steps: all_steps
      )
    end

    private

    # Chunk by ≈chunk_seconds window (SPEC §8.5).
    def chunk_segments(segments)
      window = Scribe.config.chunk_seconds * 1000
      return [ segments ] if segments.empty? || segments.last.end_ms <= window

      segments.group_by { |s| s.start_ms / window }.values
    end

    def generate_chunk(segments, frames)
      relevant_frames = frames_for(segments, frames)
      content = build_content(segments, relevant_frames)

      @last_response = @client.create_message(
        model: @model,
        system: ManualGeneration::ToolSchema::SYSTEM,
        messages: [ { role: "user", content: } ],
        tools: [ ManualGeneration::ToolSchema.definition ],
        tool_choice: { type: "tool", name: ManualGeneration::ToolSchema::NAME }
      )

      Anthropic::Client.tool_input(@last_response, ManualGeneration::ToolSchema::NAME) || {}
    end

    # Frames whose timestamp falls within the chunk window, capped for token cost
    # control (SPEC §9.4: ≤ max_images_per_call).
    def frames_for(segments, frames)
      return frames.first(Scribe.config.max_images_per_call) if segments.empty?

      lo = segments.first.start_ms
      hi = segments.last.end_ms
      in_window = frames.select { |f| f.timestamp_ms.between?(lo, hi) }
      in_window = frames if in_window.empty?
      in_window.first(Scribe.config.max_images_per_call)
    end

    def build_content(segments, frames)
      content = []
      content << { type: "text", text: transcript_text(segments) }
      content << { type: "text", text: "Candidate frame timestamps (ms): #{frames.map(&:timestamp_ms).join(', ')}" }

      frames.each do |frame|
        content << { type: "text", text: "Frame at #{frame.timestamp_ms} ms:" }
        image = image_block_for(frame)
        content << image if image
      end
      content
    end

    def transcript_text(segments)
      segments.map do |s|
        "[#{fmt(s.start_ms)}–#{fmt(s.end_ms)}] #{s.text}"
      end.join("\n")
    end

    def image_block_for(frame)
      key = frame.thumbnail_storage_key || frame.storage_key
      return nil if key.blank? || !Storage.exists?(key)

      data = Base64.strict_encode64(Storage.get(key))
      { type: "image", source: { type: "base64", media_type: "image/png", data: } }
    rescue StandardError
      nil
    end

    def fmt(ms)
      total = ms.to_i / 1000
      format("%02d:%02d", total / 60, total % 60)
    end
  end
end
