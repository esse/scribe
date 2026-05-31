module Anthropic
  # Offline stand-in for the Messages API (SPEC §15 — stub Claude so the pipeline
  # runs in dev/CI without external spend). Produces a deterministic `emit_manual`
  # tool_use response derived from the transcript segments and candidate frames
  # carried in the prompt, so the generated manual is realistic and stable.
  class FakeClient
    def create_message(model:, system:, messages:, tools: nil, tool_choice: nil, max_tokens: 4096)
      content = Array(messages.last && messages.last[:content] || messages.last["content"])
      segments = extract_segments(content)
      candidates = extract_candidate_timestamps(content)

      steps = segments.each_with_index.map do |seg, i|
        {
          "title" => "Step #{i + 1}",
          "body_markdown" => seg[:text],
          "source_start_ms" => seg[:start_ms],
          "source_end_ms" => seg[:end_ms],
          "frame_timestamp_ms" => nearest(candidates, seg[:start_ms])
        }
      end

      {
        "content" => [
          {
            "type" => "tool_use",
            "name" => ManualGeneration::ToolSchema::NAME,
            "input" => {
              "title" => "Generated User Manual",
              "summary" => "An auto-generated walkthrough based on the screen recording.",
              "steps" => steps
            }
          }
        ],
        "usage" => { "input_tokens" => 100, "output_tokens" => 200 },
        "model" => model
      }
    end

    private

    # Parse the "[mm:ss–mm:ss] text" transcript text block back into rough segments.
    def extract_segments(content)
      text_block = content.find { |b| (b[:type] || b["type"]) == "text" && (b[:text] || b["text"]).to_s.include?("–") }
      raw = text_block && (text_block[:text] || text_block["text"])
      return default_segments if raw.blank?

      raw.lines.filter_map do |line|
        if line =~ /\[(\d+):(\d+)–(\d+):(\d+)\]\s*(.*)/
          { start_ms: (($1.to_i * 60 + $2.to_i) * 1000), end_ms: (($3.to_i * 60 + $4.to_i) * 1000), text: $5.strip }
        end
      end.presence || default_segments
    end

    def extract_candidate_timestamps(content)
      block = content.find { |b| (b[:text] || b["text"]).to_s.start_with?("Candidate frame timestamps") }
      raw = block && (block[:text] || block["text"])
      raw.to_s.scan(/\d+/).map(&:to_i).presence || [ 0 ]
    end

    def nearest(candidates, ms)
      candidates.min_by { |c| (c - ms).abs }
    end

    def default_segments
      [ { start_ms: 0, end_ms: 3000, text: "Follow the steps shown in the recording." } ]
    end
  end
end
